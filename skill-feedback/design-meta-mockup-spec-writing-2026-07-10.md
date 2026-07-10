---
skill: design/meta/mockup/spec-writing/build
date: 2026-07-10
source: 真实消费仓会话复盘 + PM 连续反馈 + gstack 对照分析
status: 已消化（2026-07-10 ab5ce41fac09707668fddd45b798f3d7dba03449）
---

<!-- 状态：已消化（2026-07-10 ab5ce41fac09707668fddd45b798f3d7dba03449）；保留作历史档案 -->

# 统一构建链路与关键 Skill 反馈消化记录

## 反馈背景

本轮从真实消费仓会话 `019f3c20-5bbb-7423-a18f-dab2c1a90fff` 复盘需求讨论、构建迭代和文档收尾。PM 明确要求抓 PMAI 框架问题，不把单个消费仓的需求质量当成根因。

PM 对工作方式的最终描述是：先把需求讨论清楚，再 build；build 完成后直接看结果并做多轮修改；PM 明确定稿后，框架自动完成最终检查、提交合并和整体文档更新。prototype 与真实 product 走同一条链路，只因 build 对象不同而使用不同验收工具和方法。

参考 gstack `v1.58.5.0`、commit `11de390` 的根路由、office-hours、autoplan、design-shotgun、design-consultation、design-html、spec、ship、land-and-deploy、document-release 等机制后，确认 PMAI 应吸收上下文恢复、前提挑战、真正的交互分路、证据绑定和失败续跑，但不照搬多阶段 review gauntlet、固定问题清单、GitHub Issue 规格或 merge 前正式文档门。

## 原始反馈摘要

1. 需求讨论没有主动恢复已有方案和历史决定，PM 经常需要重复交代。
2. 问句、推测和讨论草稿会被误写进决定或规格。
3. design 仍让 PM 手动决定是否调用 meta、mockup、spec-writing，没有形成一个前台入口。
4. meta 经常只复述用户问题，缺少危险前提、反例、替代模型和推荐判断。
5. mockup 只画当前卡片或当前页面，漏掉用户详情、部门详情和完整任务路径；多稿也容易只是视觉换皮。
6. spec-writing 在成文时补决定或遗漏入口页、关联页、权限差异和异常状态；正式规格还会残留旧版正文和迭代流水账。
7. 决策账本、worktree、执行器、build contract、验收证据被呈现成第二条用户流程，PM 被连续工程菜单打断。
8. prototype 与 product 不应分成两套生命周期；只应切换构建对象与验收适配器。
9. PM 看 build 结果后的多轮修改，应只跑受影响快检；明确说“定稿 / 可以提交 / 可以合并”后再跑完整检查。
10. PM 的定稿表达已经授权提交和合并，不应二次确认，也不应要求手动调用 `/pmai-build-close`。
11. 验收证据必须和最终 source hash、implementation commit 绑定；产品决定变化后旧证据必须失效，工具受限不能伪装为通过。
12. merge 冲突和 landed 后文档失败都要可恢复；文档失败不能重复 merge。
13. 正式文档只能在实现进入 main 后整体更新，只描述当前事实；历史进入 Git 和 `decisions.md`。
14. 关键 Skill 不能继续依赖 PM 反复引导或手动修改，需要真实失败样本、静态合同、会话评测和 judge 作为长期回归基线。

## 消化结果对账表

| # | 反馈类目 | 落地状态 | 落地位置 | 消化结果 |
|---|---|---|---|---|
| 1 | design 主动恢复旧上下文 | 已落地 | `scripts/context-pack.py`、`skills/_shared/context-reconstruction.md`、`skills/design/SKILL.md` | design 开场先编译确定性上下文，消费 active / superseded 决定、未决问题、实现入口和输入 hash；已有答案不再重复问 |
| 2 | 问句不能成为决定或规格 | 已落地 | `scripts/context-pack.py`、`skills/_shared/decision-policy.md`、`skills/_shared/decision-record.md` | 只有 PM 明确回答或接受推荐才形成决定；问题句、推测、讨论草稿被拒绝为决定，推翻旧决定显式标记 supersede |
| 3 | design 是唯一需求讨论前台 | 已落地 | `skills/design/SKILL.md`、`skills/design/references/design-method.md` | meta、mockup、spec-writing 改为按需内部能力，完成后返回 design；不再让 PM 拼接命令或选择是否保存建造依据 |
| 4 | meta 必须产生新判断 | 已落地 | `skills/meta/SKILL.md`、`skills/meta/references/product-meta-thinking.md`、`skills/meta/references/problem-framing.md` | 固定产出当前判断、隐含前提、最危险前提、反例、替代模型、代价和推荐；没有新判断、反例或取舍即视为失败 |
| 5 | mockup 覆盖完整任务且真分路 | 已落地 | `skills/mockup/SKILL.md` | 输入合同要求现有设计、入口、主路径、上下游页面、权限和边界状态；有真实交互岔路才多稿，无岔路只给一套推荐稿 |
| 6 | spec-writing 只编译已确认事实 | 已落地 | `skills/spec-writing/SKILL.md`、`skills/_shared/consistency-scan.md` | 新增对象—动作—状态—权限—页面覆盖矩阵；未决项返回 design；`spec.md` 只保留当前事实，并支持建造前编译与 landed 后事实对账 |
| 7 | 工程基础设施后台化 | 已落地 | `skills/build/SKILL.md`、`skills/build-close/SKILL.md`、`templates/AGENTS.md.tmpl` | worktree、执行器、合同和证据不形成 PM 菜单；完整 build 自动选隔离环境和执行器，`build-close` 仅保留兼容与恢复入口 |
| 8 | prototype / product 共用生命周期 | 已落地 | `scripts/_lib/stages.py`、`scripts/build-contract.py`、`scripts/acceptance-profile.py` | 统一 `designing → ready_to_build → building → iterating → final_check → landed → documenting → complete`；只按 target kind 切换验收 profile |
| 9 | 多轮修改快检、定稿全检 | 已落地 | `skills/build/SKILL.md`、`scripts/acceptance-profile.py` | iterating 只跑受影响的快速检查；PM 定稿后才运行完整 required checks |
| 10 | 自然语言定稿自动 finalize | 已落地 | `scripts/_lib/term-detector.py`、`skills/_shared/term-detector/SKILL.md`、`skills/build/SKILL.md`、`scripts/land-work.sh` | “定稿 / 可以提交 / 可以合并”直接进入最终检查、合入 main 和 landed 后文档编译，不二次确认、不要求手动 close |
| 11 | 证据绑定与失效 | 已落地 | `scripts/build-contract.py` | 合同 v2 绑定 approved source hash、design revision、implementation commit 和 evidence；accepted delta 或新 commit 自动使旧证据失效，limited / skipped 只能记 exception |
| 12 | 冲突与文档失败续跑 | 已落地 | `scripts/land-work.sh`、`scripts/build-contract.py`、`scripts/status-view.py` | merge 冲突保留 `final_check` 和隔离工作区；文档失败保留 `landed/docs_pending`，恢复时从文档影响地图继续，不重复 merge |
| 13 | main 后整体更新正式文档 | 已落地 | `scripts/doc-impact.py`、`skills/spec-writing/SKILL.md`、`skills/_shared/consistency-scan.md` | 基于 landed diff、合同和 accepted deltas 生成影响地图；对象、动作、状态、权限、页面、术语逐项 covered 或明确 no-change，文档单独提交 |
| 14 | 真实失败样本与评测基线 | 已落地 | `evals/cases/`、`evals/touchfiles.json`、`scripts/skill-eval.py`、`tests/test-skill-eval.sh` | 固化 14 个真实失败场景；静态案例作为提交门，session runner / LLM judge 缺失时显式 skip，require 模式显式失败 |

## 真实失败样本与回归映射

| 会话问题 | 回归案例 |
|---|---|
| 问句被误当决定 | `evals/cases/decision-question-not-fact.json` |
| 已有方案未主动恢复 | `evals/cases/design-recovers-history.json` |
| mockup 漏用户详情和部门详情 | `evals/cases/mockup-covers-full-task.json` |
| 连续 worktree / 执行器 / 保存依据菜单 | `evals/cases/no-internal-menus.json` |
| meta 只复述、补丁味需求不回根因 | `evals/cases/meta-judgment-model-static.json`、`evals/cases/patch-smell-routes-meta.json` |
| spec 漏入口页、关联页、状态和权限 | `evals/cases/spec-coverage-map.json` |
| PM 仍需手动 close | `evals/cases/natural-language-finalize.json` |
| prototype 与 product 被拆成两条流程 | `evals/cases/prototype-product-same-lifecycle-static.json` |
| 设计变化后旧证据仍被复用 | `evals/cases/evidence-invalidation-static.json` |
| merge 冲突或文档失败无法安全续跑 | `evals/cases/merge-conflict-recovery-static.json`、`evals/cases/docs-pending-resume-static.json` |
| 正式文档残留迭代流水账 | `evals/cases/current-facts-only.json` |

## 已确认的框架决策

- 用户主链路只有一条；决策账本、context pack、worktree、合同和证据是后台基础设施。
- 一次 build 只有一个主要对象：prototype 或 product；生命周期相同，验收方法按对象和风险自适应。
- design 自动按需调用 meta、mockup、spec-writing；不新增公开命令让 PM 记忆。
- 只有真实产品模型岔路、one-way door 和改变 PM 已明确方向时立即提问；其余由 AI 给推荐并推进。
- 正式文档只在实现进入 main 后更新，只描述 main 已存在的事实。
- gstack 只作为方法参考和可选证据生产工具，不成为 PMAI 的状态、决定或收尾权威。
- 不新增 `decisions.jsonl` 或第二套状态机；合同 v1 继续可读，旧消费仓渐进升级。

## 实施与验证

- 主实现提交：`ab5ce41fac09707668fddd45b798f3d7dba03449`
- 完整测试：`459 passed / 0 failed`
- 额外检查：Python 语法、Shell 语法、`git diff --check`、机器绑定路径扫描均通过。
