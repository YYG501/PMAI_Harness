---
skill: build-close
反馈来源: 会话内直接反馈（模式 B）· 2026-06-28 datou /pmai-build-close 实战
消化: 2026-06-28
---

# build-close skill 反馈 · 2026-06-28

> 来源：PM 反馈消费仓里 `/pmai-build-close` 把普通实现分支上的提交、未完成验证和未合回主线的状态说成“已收口”，并且 build 阶段没有把执行方式 / 执行器 / 验收结果记录成 close 可读取的上下文。

## 消化结果对账表

| # | 反馈 | 落地状态 | 落地位置 | 说明 |
|---|---|---|---|---|
| 1 | build-close 不能根据当前分支或有没有 worktree 猜收尾方式。 | 已落地 | `skills/build-close/SKILL.md` 入口判断 / Rules；`scripts/close-work.sh` | 新增 build 合同校验，收尾方式只看 `.work-meta.json:build.mode`。 |
| 2 | build 开始时应记录 PM 已选择的执行方式和执行器，否则 close 没有合同可遵守。 | 已落地 | `skills/build/SKILL.md` 步骤 2.5；`scripts/build-contract.py` | build 在实现前写入 `anchor` / `mode` / `executor` / `branch` / `worktree` / `baseline_sha`。 |
| 3 | build 验收后应记录实现提交和 PM 验收结果，否则不能进入最终 close。 | 已落地 | `skills/build/SKILL.md` 步骤 8；`scripts/build-contract.py validate-close` | close 前要求 `implementation_commit` 和 `pm_accepted_at` 都存在。 |
| 4 | 普通非 main 分支或 worktree 丢失不能降级成“只沉淀，不合回”。 | 已落地 | `scripts/close-work.sh`；`tests/test-close-work.sh` | `mode=worktree` 但记录分支 / worktree 缺失时拒绝，提示恢复上下文，不退化为 main 直收。 |
| 5 | 不应为了 status 时间线写“已收口状态”。 | 已落地 | `skills/build-close/SKILL.md` 步骤 5.4 / Rules | `.work-meta.json` 只表示 active，最终由 close-work 删除；未落主线不写完成态。 |

<!-- 状态：已消化（2026-06-28，未提交）；保留作历史档案 -->
