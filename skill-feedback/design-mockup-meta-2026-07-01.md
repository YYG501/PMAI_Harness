---
skill: design/mockup/meta
date: 2026-07-01
source: 会话内 PM 反馈 + 真实消费仓 session 复盘
status: 已消化（2026-07-01；见提交记录）
---

<!-- 状态：已消化（2026-07-01；见提交记录）；保留作历史档案 -->

# design / mockup / meta 通用优化反馈消化

## 原始反馈摘要

PM 复盘最新消费仓真实会话后指出：

- 前面的思路分析没有先还原真实业务对象，过早进入页面方案。
- `/pmai-mockup` 和 `/pmai-meta` 没有被主动调用。
- mockup 没有发挥 gstack shotgun 的发散能力。
- gstack browser 在 Codex runtime 里一直看起来不可用，需要实测判断。
- meta 的多视角分析没有真正使用子 Agent。
- 什么时候改原型、什么时候改文档，没有清晰流程。

PM 后续明确：不需要增加独立“行动前路由层”，问题应回到 `/pmai-design` 本身；忽略“会话导出被提交进业务 commit”问题。

## 消化结果对账表

| # | 反馈类目 | 落地状态 | 落地位置 | 说明 |
|---|---|---|---|---|
| 1 | design 过早进入方案，缺业务对象建模 | 已落地 | `skills/design/SKILL.md`、`skills/design/references/design-method.md` | 新增业务对象建模硬门：原始输入、业务对象、对象关系、状态、下游判断、真相源 |
| 2 | design 缺少 meta / mockup / build / skill-improve 分流 | 已落地 | `skills/design/SKILL.md`、`design-method.md` | 工作类型判断升级为分流硬门，明确五类下游 |
| 3 | mockup 发散性不足，gstack 没被真正用起来 | 已落地 | `skills/mockup/SKILL.md` | 默认优先 gstack-shotgun，gstack 不可用时走 PMAI 内部 shotgun fallback |
| 4 | gstack browser 是否可用需要实测与诊断 | 已落地 | `scripts/check-gstack-browser.sh`、`bin/pmai-doctor` | 新增诊断脚本，区分 Codex sandbox `EPERM` 和 gstack 损坏；显式 `--smoke` 才启动 browse / design board |
| 5 | meta 多视角不等于多 Agent | 已落地 | `skills/meta/SKILL.md`、`skills/meta/references/thinking-toolbox.md` | 区分单主控多视角和多 Agent 压测；无子 Agent 时必须声明退化 |
| 6 | 文档和原型边界不清 | 已落地 | `skills/design/SKILL.md`、`skills/mockup/SKILL.md`、`templates/AGENTS.md.tmpl` | design 只改设计文档，mockup 只写 `mockups/`，主原型改动转 build 或 PM 明确小改确认 |
| 7 | 消费仓 Codex 规则需同步 | 已落地 | `templates/AGENTS.md.tmpl` | 同步 design 主入口、mockup 边界、meta 退化声明、gstack sandbox 说明 |

## 采纳决策

- 不新增独立“行动前路由层”；分流责任放回 `/pmai-design`。
- `/pmai-mockup` 的核心价值是发散探索和对比，不是单方案草图。
- gstack 是 mockup 的优先引擎；不可用时 PMAI 自己补齐多方向比稿流程。
- `/pmai-meta` 不能假装多 Agent；有子 Agent 才称多 Agent，否则明确退化。
- 本轮不处理会话导出进入业务 commit 的问题。
