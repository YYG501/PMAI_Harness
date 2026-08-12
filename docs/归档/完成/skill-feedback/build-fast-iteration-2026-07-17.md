---
skill: build
date: 2026-07-17
source: 真实消费仓会话复盘（模式 B）
session_id: 019f49b7-088b-75c3-a0e4-0c05ca61f3fd
---

<!-- 状态：已消化（2026-07-17，commit 99ed48c）；保留作历史档案 -->

# Build 快速迭代与定稿验收混跑反馈

## 原始反馈

PM 在真实原型构建中发现：慢的主要不是编译本身，而是框架把首次实现、PM 看结果期间的小改、production build、完整浏览器验收和服务恢复混成同一轮 build。文案、布局和按钮改一点，也重复承担接近完整定稿的成本；production build 与 dev server 共用构建缓存时还会破坏正在运行的页面，进一步触发重启和浏览器恢复。

PM 确认的目标：小改 2–5 分钟可看，交互改动 5–10 分钟可看；完整 production validation 只在明确“定稿 / 可以提交 / 可以合并”后对冻结版本统一运行一次。

## 消化结果对账表

| # | 反馈类目 | 原状态 | 剩余 gap | PM 决策 | 落地位置 |
|---|---|---|---|---|---|
| 1 | 缺少 PM 定稿硬门 | ❌ 未落地 | `review-ready` 可在 PM 查看期间生成，完整验收会反复执行 | 采纳 | `scripts/build-contract.py` contract v4：`request-finalization / resume-iteration` |
| 2 | 快检与定稿验收共用证据 | ❌ 未落地 | 只有 `required_checks + evidence`，无法机器区分两条车道 | 采纳 | `scripts/acceptance-profile.py` schema v2；合同 `iteration_checks / final_checks` 与两层 evidence |
| 3 | 小改反复派发外部 builder | ⚠️ 部分落地 | 当前会话可选，但 active build 反馈仍可能重新派发并重复读仓库 | 采纳 | `skills/build/SKILL.md` §4-5；消费仓 AGENTS / CLAUDE 模板 |
| 4 | production build 污染 dev server | ❌ 未落地 | 验收与开发共用 worktree 和构建缓存 | 采纳 | `scripts/final-validation.py`；`skills/build/SKILL.md` §6 |
| 5 | 没有分阶段耗时和 time-to-preview | ❌ 未落地 | 无法判断慢在准备、实现、快检、构建还是浏览器验收 | 采纳 | `scripts/build-timing.py`；`.pm-workflow/audits/<模块>/timing.json` |
| 6 | PM 被完整验收阻塞 | ⚠️ 部分落地 | 文案写“先展示”，流程却要求查看期间后台完成完整验收 | 采纳 | build 快速回执改为“已修改，可刷新查看”；2–5 / 5–10 分钟仅预警 |

未采纳项：无。

## 最终规则

> PM 看结果期间只走快速迭代：当前会话直接修改，复用 dev server 与浏览器，只跑 typecheck 和当前页面走查，完成后先让 PM 刷新。PM 明确请求定稿后，才冻结 implementation commit，在独立 validation worktree 统一运行一次 production build 和完整验收，再生成 review-ready 并落地主线。

## 验证

- acceptance profile：prototype / product 同时生成 `iteration_checks / final_checks`，旧 `required_checks` 仅作兼容别名。
- build contract：定稿请求前拒绝 final evidence；验收修复 commit 自动重绑定稿意图；PM 新反馈可显式恢复快速迭代。
- validation helper：冻结 commit 在 detached worktree 执行，active worktree 不产生 production artifact，完成后安全清理。
- timing helper：阶段耗时与 time-to-preview 可汇总；超过 5/10 分钟只产生 warning，命令仍成功。
