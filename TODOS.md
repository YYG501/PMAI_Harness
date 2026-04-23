# TODOS

## v2: 状态物化到 worktree 生命周期

**What:** 把 task 状态从「markdown 字段」升级为「文件系统约束」。具体：
- `/task-confirm`（待确认→执行中）才 `git worktree add`
- `/task-submit`（执行中→待验收）立即 `git worktree lock` 或 `chmod -R a-w`
- PM 打回（待验收→执行中）unlock
- `/close-task`（待验收→已完成）`git worktree remove`

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
- 所有 task 状态字段停在"待确认"，PM 未见验收信息
- 这次用 v1 的 adapter gate + close-task 事件流审计（I-CT7/I-CT8）兜底；数据还不足支撑架构大改，先观察

**Depends on / blocked by:**
- v1 护栏上线后积累 3-5 次真实事件数据再决定
- 或 v1 防御被证明存在结构性漏洞
- 需验证 `git worktree lock` 对 Codex CLI 的约束力

**下次接任者要知道:**
- 当前 worktree lifecycle：`create-task-worktree.sh` 在 `/task-confirm` 时建
- serial 约束（I-TT2）只在 `task-transition.py` 的 `待确认→执行中` 时校验——不走 transition 就没校验
- `git worktree lock` 是 git 自带功能，会拦 `git worktree remove` 但不会拦 fs-level 写入；真实约束力需 POC
- chmod 方案和 lock 方案的 tradeoff 要考虑
