# docs/ 导航

> docs/ 目录按**文档生命周期**分类：起草 → 执行 → 归档（完成 / 废弃）。本文件是各目录的活索引。
>
> **不在 docs/ 的关键文档**（顶层）：`CLAUDE.md`（章程）、`RUNTIME.md`（运行时状态）、`TODOS.md`（待决清单）、`INVARIANTS.md`（不变量）、`CHANGELOG.md`、`框架同步-SOP.md`、`README.md`

---

## 设计/ — 起草中

| 文件 | 说明 |
|---|---|
| [`_模板-方案.md`](./设计/_模板-方案.md) | 唯一设计文档模板（§0 痛点锁 + §1-§N 方案主体 + §X Review Findings + §Y 决议日志），起手用 |
| [`框架分发与全局安装.md`](./设计/框架分发与全局安装.md) | **v1.1 实施中**（2026-05-26）—— 框架从"cd 生成器仓"hack 切到"pmai 全局 install + 任意 cwd 跑 /pmai-*"；T0 POC ✅ / T1 ✅ bin/pmai-* 6 脚本 + VERSION 0.1.0 / T2 ✅ init-project.sh PMAI_HOME / T4 ✅ 文档更新 / T3+T5（消费仓同步与迁移）PM 决议暂缓 |

> **起手新设计**：`cp docs/设计/_模板-方案.md docs/设计/<主题>.md`

---

## 执行中/ — PM 已锁，准备/正在 ship

（暂无）

---

## 归档/完成/ — 已落地

**关键子目录**：

| 子目录 | 说明 |
|---|---|
| [`modulespec-维护/`](./归档/完成/modulespec-维护/) | D13 modulespec 维护方案（主方案 + 验证脚本 + 决策路径-v2到v3.2）— 2026-05-16 全部落地 |
| [`v0/`](./归档/完成/v0/) | PMAI 起点原始草稿（需求 / 设计 / 需求-v0-原始草稿）|

**单文件（按主题，2026-04~05 v3.5 收口前的设计档）**：

| 主题 | 文件 | 现役承接 |
|---|---|---|
| **原型简化项登记机制 v2** | [`原型简化项-机制.md`](./归档/完成/原型简化项-机制.md) | 2026-05-24 T1-T8 全包落地（398/0）—— `templates/implementation-design.md.tmpl` 段 1.5 + 7 处下游 SKILL wiring + `scripts/check-doc-pm-view.py --simp-scope` |
| **D-i office-hours 跨 Stage 1+2 集成 v4** | [`office-hours-跨stage1-2集成.md`](./归档/完成/office-hours-跨stage1-2集成.md) | 2026-05-25 vp-1～vp-7 全包落地（412/0）—— `_lib.state.{get,set}_stage_source` helper + `req-stage-gate` Stage 1→2 合二为一选择门 + 分流 A/B + office-hours bridge snapshot + `.req-meta.json` 3 字段（stage{N}_source/_tool/_source_origin）+ I-RT9 不变式 + 下游 9 处通用化"stage 2 真相源" |
| **D-iii attachments AI 接管 v2** | [`attachments-AI-接管.md`](./归档/完成/attachments-AI-接管.md) | 2026-05-25 vp-1～vp-7 全包落地（425/0）—— `_lib/attachments.py` helper（copy/register/list/is_seen/remove/replace + SENSITIVE_PATH_PATTERNS denylist + MAX_FILE_SIZE_MB=50 hard cap）+ `attachments-upload.md` 单一真相源 + 7 stage SKILL trigger 0 段 + `.req-meta.json:attachments_seen` 字段 + I-RT10 不变式 + B 分支 trigger 0 disable（C4 cross-design 防护）|
| **D-iv 入口与全流程体验顺畅性** | [`入口与全流程体验顺畅性.md`](./归档/完成/入口与全流程体验顺畅性.md) | 2026-05-25 批 1 + 批 2 全包技术 vp 落地（**446/0**，+21 cases）—— M1 init-project 一气呵成（vp-1~vp-6）+ M2 banner-rules.md + Decision gate label（vp-7/vp-8）+ M4 askuser-rules.md（vp-10）+ M5 status-view --narrative + CLAUDE.md「Session 起始播报」（vp-11）；**M3 砍**（codex C-1：req-stage-gate 续跑模式已默认覆盖痛点）；7 个核心 SKILL 顶部加 banner + askuser 指针；plan-eng-review Round 1（claude + codex outside voice）16 finding 全 ACCEPT；剩 vp-5b/vp-13 PM 手动验收同步消费仓后跑 |
| skill 读取收敛 | [`设计-skill读取收敛.md`](./归档/完成/设计-skill读取收敛.md) | commit be47fca + PM-VIEW-RULES §9.1 |
| 框架同步 | [`设计-框架同步.md`](./归档/完成/设计-框架同步.md) | 实战 d0aa6c1 + 框架同步-SOP.md |
| PM 手动新窗口执行 | [`设计-PM手动新窗口执行.md`](./归档/完成/设计-PM手动新窗口执行.md) | create-task-worktree.sh + task-confirm skill |
| 执行者可选 | [`设计-执行者可选.md`](./归档/完成/设计-执行者可选.md) + [`实施计划-执行者可选.md`](./归档/完成/实施计划-执行者可选.md) | `scripts/exec-adapters/` 4 个适配器 |
| close-task 优化 | [`设计-close-task优化.md`](./归档/完成/设计-close-task优化.md) | close-task skill |
| quick-fix | [`设计-quick-fix.md`](./归档/完成/设计-quick-fix.md) | skills/quick-fix + scripts/quick-fix.sh |
| stage2-3 skill 改造 | [`设计-stage2-3-skill改造.md`](./归档/完成/设计-stage2-3-skill改造.md) | req-analysis skill |
| 组件复用闭环 | [`设计-组件复用闭环.md`](./归档/完成/设计-组件复用闭环.md) | task-execute skill |
| 功能规格文档增强 | [`设计-功能规格文档增强.md`](./归档/完成/设计-功能规格文档增强.md) | doc-update skill + docs/modules |
| 原型与系统双模式 | [`设计-原型与系统双模式.md`](./归档/完成/设计-原型与系统双模式.md) | 部分吸收到 工程视图档位差异化 |
| 新两文件格式对齐 | [`设计-新两文件格式对齐.md`](./归档/完成/设计-新两文件格式对齐.md) + [`阶段1-动手plan-parser-task-transition迁移.md`](./归档/完成/阶段1-动手plan-parser-task-transition迁移.md) | `.engineering.md` 双文件 + 多 SKILL |
| 工程视图档位差异化 | [`设计-工程视图档位差异化.md`](./归档/完成/设计-工程视图档位差异化.md) | detect-project-structure.py |
| 实现程度与格式对齐 | [`实施计划-实现程度与格式对齐.md`](./归档/完成/实施计划-实现程度与格式对齐.md) | templates/CLAUDE.md.tmpl |
| stage3 改进 | [`stage3-改进计划.md`](./归档/完成/stage3-改进计划.md) | req-analysis skill |
| **GSD 借鉴研究分析** | [`gsd-借鉴-研究分析.md`](./归档/完成/gsd-借鉴-研究分析.md) | 研究 v3.10 完成（3 项识别，其中 ADR 项被文档目录整理替代） |
| **GSD 借鉴实施方案** | [`gsd-借鉴-实施方案.md`](./归档/完成/gsd-借鉴-实施方案.md) | v3 方案 2 项全落（commits 8bb7b00 state.py + 10bdf71 lark-adapter + 214291f 补漏测试，run-all 368/0） |
| DX 审计 | [`DX-AUDIT-2026-05-08.md`](./归档/完成/DX-AUDIT-2026-05-08.md) | 审计时点快照已完成 |

**2026-05 管线重构批次（GSD-review §8 + PRD 体系收敛 + 独立机制；2026-05-22 归档）**：

| 主题 | 文件 | 现役承接 |
|---|---|---|
| 管线重构总纲 | [`管线重构-GSD-review.md`](./归档/完成/管线重构-GSD-review.md) | §8 六步全包落地（CHANGELOG 2026-05-22）|
| delta-2/4 PRD/solution 对调 | [`PRD-solution-对调.md`](./归档/完成/PRD-solution-对调.md) | `/pmai-project-solution` + `/pmai-prd-writing` 前移 stage 3 |
| delta-3 task-spec 重构 | [`task-spec重构.md`](./归档/完成/pmai-task-spec重构.md) | task 单文件 typed contract（三区 + `task_format` 标记）|
| delta-7 req 级事件流 | [`req级事件流-delta7.md`](./归档/完成/req级事件流-delta7.md) | `scripts/req-events.py` + `req-events.jsonl` |
| delta-8 实现设计视图 | [`实现设计视图-HOW安家.md`](./归档/完成/实现设计视图-HOW安家.md) | `/pmai-implementation-design` + `templates/implementation-design.md.tmpl` |
| delta-9 跨功能产品规则 | [`项目产品规则-delta9.md`](./归档/完成/项目产品规则-delta9.md) | `templates/PRODUCT-RULES.md.tmpl` + stage 4 gap-check |
| accept 闸门 | [`accept闸门.md`](./归档/完成/accept闸门.md) | `task-transition.py` 验收前执行证据校验 |
| 证据修复命令 | [`证据修复命令.md`](./归档/完成/证据修复命令.md) | `task-transition.py --repair-evidence` |
| PRD 体系收敛 v5 | [`PRD-体系收敛.md`](./归档/完成/PRD-体系收敛.md) | 砍 `docs/prd.md` 整套 + `PROJECT.md` 6 节（11 commit）|
| attachments 机制 v0（已被 v2 helper 化升级承接）| [`attachments-机制.md`](./归档/完成/attachments-机制.md) | commit `65329d0` 独立机制 v0 落地；**2026-05-25 D-iii v2 helper 化升级** → 现役见 `attachments-AI-接管.md` |

---

## 归档/废弃/ — 被否决，不实施

| 文件 | 否决理由 |
|---|---|
| [`设计-Superset独立Claude执行.md`](./归档/废弃/设计-Superset独立Claude执行.md) | 明标 DEPRECATED（被 PM 手动新窗口取代） |
| [`设计-stage5-6-task循环.md`](./归档/废弃/设计-stage5-6-task循环.md) | "历史设计备忘 + 讨论中"，部分被替代 |
| [`task-spec-早期截断.md`](./归档/废弃/pmai-task-spec-早期截断.md) | "设计中"半年沉寂；D13 已解 task-spec 相关问题 |

---

## 历史决策回填说明

D1-D12 / D14-D15 + 已归档的设计稿 **没有批量回填到决策模板格式**。

理由：
- 真痛点 EVIDENCE 只举 D13 一条
- 机械回填历史档 6 个月后大部分没人查 → 治理幻觉
- **触发式补**：PM 某次查不到决策根因时，为那条决策在原归档文档加一段补充，或新建 `<主题>/决策回填.md`

**查不到决策根因时**：
1. 先 grep [`设计/`](./设计/) 起草中
2. 再 grep [`执行中/`](./执行中/) 当前活跃
3. 再 grep [`归档/完成/`](./归档/完成/) 已落地档案
4. 再 grep [`归档/废弃/`](./归档/废弃/) 被否决档案
5. 再 grep `RUNTIME.md` / `TODOS.md` 散落决策
