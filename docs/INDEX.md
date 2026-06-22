# docs/ 导航

> docs/ 目录按**文档生命周期**分类：起草 → 执行 → 归档（完成 / 废弃）。本文件是各目录的活索引。
>
> **不在 docs/ 的关键文档**（顶层）：`PRODUCT.md`（产品定位真相源）、`CLAUDE.md`（章程）、`RUNTIME.md`（运行时状态）、`TODOS.md`（待决清单）、`INVARIANTS.md`（不变量）、`CHANGELOG.md`、`README.md`

---

## 设计/ — 起草中

| 文件 | 说明 |
|---|---|
| [`_模板-方案.md`](./设计/_模板-方案.md) | 唯一设计文档模板（§0 痛点锁 + §1-§N 方案主体 + §X Review Findings + §Y 决议日志），起手用 |
| [`框架分发与全局安装.md`](./设计/框架分发与全局安装.md) | **v1.1 实施中**（2026-05-26）—— 框架从"cd 生成器仓"hack 切到"pmai 全局 install + 任意 cwd 跑 /pmai-*"；T0 POC ✅ / T1 ✅ bin/pmai-* 6 脚本 + VERSION 0.1.0 / T2 ✅ init-project.sh PMAI_HOME / T4 ✅ 文档更新 / T3+T5（消费仓同步与迁移）PM 决议暂缓 |
| [`PMAI重构方向-office-hours收敛.md`](./设计/PMAI重构方向-office-hours收敛.md) | **六步重构方向真相源**（office-hours 收敛）—— per-req 四阶段（范围确认 / build / 复审 / 沉淀）+ 上下文脊柱（PRODUCT-STATE / 主原型 / DESIGN）+ 三条上坡路 + 三道审 + 反向 PRD 沉淀。2026-05-30 主体 + follow-on 全落地（branch `reshape-office-hours`，543/0）；**合 main 后归档到 完成/** |
| [`PMAI重构-实施清单.md`](./设计/PMAI重构-实施清单.md) | **六步重构落地真相源** —— skill 去留 + gstack 接入 + worktree 模型 + D-decisions + §7 复盘 scope（站点爬 / 对齐线上 / checks 引擎 / 产物层）。2026-05-30 全落地；**合 main 后归档到 完成/** |
| [`stage编号清理与banner去号.md`](./设计/stage编号清理与banner去号.md) | **已落地（2026-06-04，待 PM 总审归档）**—— 清三套编号混用（六步①-⑥ / 内部 stage1-4 / 旧7-stage 4A·5·6·7）导致 runtime AI 推过头：prose 去裸数字 + input-flow §9 加映射列 + banner 去 stage 号（state.py:433 单点）+ lint hook；「六步」名保留。quick-fix drift-scan 产物链停旧机 = DEFER 单独议题 |
| [`分档运行与沉淀层.md`](./设计/分档运行与沉淀层.md) | **已落地（2026-06-04，待 PM 总审归档）**—— **演进母文档运行模型 + 统一另三份子设计的共同前提**。痛点 = 沉淀只挂 full-req 末尾(close 唯一写入口, code 实锤 close-req:90)，但 PM 真实用法分档(大量 main 直接改不进 req) → 轻档绕过沉淀点 → 四痛(真相源乱/脊柱入口不可见/决策困讨论稿/mock变体找不回)。方案：① 分档谱(轻 main 直接改 / 中 轻 req 直建 / 重 完整 req)② 沉淀触发从 close-only 扩到每档(机制不新造,补触发点)③ mock 变体留存+找回(母文档生成但不持久化,子设计零覆盖)。§1.4 待抠=轻档"轻沉淀"具体形态。实证 wf_52e02581(对抗验证已纠混合航道/脊柱不可见措辞) |
| [`项目奠基决策记录.md`](./设计/项目奠基决策记录.md) | **已落地（2026-06-04，R5 拍定，待 PM 总审归档）**—— 新增「项目级冻结决策记录」文档类（`docs/decisions/<日期>-<slug>.md`），承接奠基轮"为什么这么拼"的理路（护城河 / 交互咬合 / 机制整体 / 演进故事）；脊柱接不住、防腐铁律禁活文档 → 走冻结档。产出触发：strategy/init-project 方向讨论 + close-req 步骤2 理路类。PM 已选「冻结」方向 |
| [`build直建轻车道.md`](./设计/build直建轻车道.md) | **草稿 v1 / §0 已锁**（2026-06-01）—— 读 GSD 真源码后重写。根因=结构放错地方（用了 GSD 反模式的逐层转写链 req-plan→task-plan→task-spec + 缺了 GSD 的对抗验证网），非"层多"。方案 4 条：A 单块/多块叉口(task-plan)、B req-plan 升「自包含实现方案」(契约当数据)、C 扩 coverage-reviewer 成对抗网(字段级+Wired+跨req集成审)、D 重锚 per-task→req-build。blast radius 中心=INVARIANTS 五组+状态机+~18 测试(非 prose)。已决：R1 选 A 路(轻量信封当网载体)、task-plan 退役(拆/不拆挪进实现方案、拆分逻辑变「执行计划」节)。§0 已锁、待 review。实证 wf_ee98a18b/461ad10d/85033273/2bdd0fea |
| [`文档治理与知识棘轮.md`](./设计/文档治理与知识棘轮.md) | **已落地（2026-06-04，待 PM 总审归档）**—— 元目标"聊天 AI 知道产品 + 产出积累"的地基。痛点 = 文档治理隐式散在 4 处无成文模型 + 跨 req/跨 close 知识棘轮漏（后面读不到前面的讨论/决策/遗留）。方案：成文「文档地图」(4 类+存放+读取) + 知识棘轮 close 三出口(耐久→脊柱 / 理路→决策记录 / 遗留→TODO) + 决策落点收敛成一条管道。G2(遗留孤儿)+G3(无成文模型) 本设计独有，G1/G4 联动决策记录/build轻车道。grep grounded(new-req:213 / close-req:76,120) |

> **起手新设计**：`cp docs/设计/_模板-方案.md docs/设计/<主题>.md`

**参考 / 留档**（非生命周期设计文档）：

| 文件 | 说明 |
|---|---|
| [`build-audits-编排与自测.md`](./build-audits-编排与自测.md) | build 三道审编排 `scripts/build-audits.py` 参考（LLM/脚本边界 + 规范化结果 schema 契约）+ 2026-05-31 自测留档（真实 manifest / 合成报告 / 守卫验证）。脚本已落地（572/0），真 req build spike 验证待做 |

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
| **GSD 参考调研笔记** | [`GSD-参考调研.md`](./归档/完成/GSD-参考调研.md) | 原始调研笔记，已并入上面两份 gsd-借鉴 落地；2026-05-30 从根目录归档 |
| DX 审计 | [`DX-AUDIT-2026-05-08.md`](./归档/完成/DX-AUDIT-2026-05-08.md) | 审计时点快照已完成 |

**2026-05 管线重构批次（GSD-review §8 + PRD 体系收敛 + 独立机制；2026-05-22 归档）**：

| 主题 | 文件 | 现役承接 |
|---|---|---|
| 管线重构总纲 | [`管线重构-GSD-review.md`](./归档/完成/管线重构-GSD-review.md) | §8 六步全包落地（CHANGELOG 2026-05-22）|
| delta-2/4 PRD/solution 对调 | [`PRD-solution-对调.md`](./归档/完成/PRD-solution-对调.md) | `/pmai-strategy` + `/pmai-prd-writing` 前移 stage 3 |
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
| [`task执行自动化与文档精简.md`](./归档/废弃/task执行自动化与文档精简.md) | 2026-05-28 前稿，方向已并入 office-hours 收敛 reshape 并落地（见 `设计/PMAI重构*`），草稿归档 |
| [`产品现状与主原型.md`](./归档/废弃/产品现状与主原型.md) | 2026-05-28 前稿（§0 已锁），范式直接演进成 reshape 并落地，草稿归档 |
| [`框架同步-SOP.md`](./归档/废弃/框架同步-SOP.md) | 手动同步流程，**DEPRECATED**；pmai install/upgrade 承接，`pmai sync` 落地后彻底退役；2026-05-30 从根目录归档 |
| [`误粘-cursor聊天记录.md`](./归档/废弃/误粘-cursor聊天记录.md) | 误粘进根目录的 Cursor 聊天记录（非设计文档，与 PMAI 无关），留档备查 |

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
