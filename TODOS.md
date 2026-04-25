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

---

## v3.5: Superset MCP 启独立 Claude 执行 task（serial）

**Status (2026-04-25):** 🟢 **Plan 收敛完成**，未实施。详见 `设计-Superset独立Claude执行.md`。

**What:** `/task-confirm` 通过 Superset MCP `start_agent_session_with_prompt` 启动独立持久 Claude 终端 pane，cwd 绑定 task worktree。新 Claude 自己同步跑 codex（`Bash run_in_background + Monitor`）。完成后 append 事件到 `.runs/events/<task>.jsonl`。主 Claude 用 ScheduleWakeup adaptive + UserPromptSubmit hook 扫事件流收口。

**Why:** 解决 v1 subagent 短命载体问题（2026-04-22 / 2026-04-24 事件根因），同时保持 v3 改动量的 40%（serial 不并行，删 mutex / boot epoch / PGID 树杀 / `/task-abort`）。

**关键决策:**
- D0 暂不并行（serial 单线）
- D1 接受 Superset SaaS 隐私边界（只传 workspaceId / prompt / agent 类型；task 内容/代码 diff/codex 输出全在本地）
- D2 选 B：保留我们 `create-task-worktree.sh`，Superset 通过 adoption 路径接管已有 worktree
- Q1 ✅ Superset 启的 Claude 是持久 REPL（`claude --permission-mode acceptEdits`）
- Q3 ❌ 无完成通知 → 自建 sentinel/事件流（复用 v3 §2.2/§2.4/§2.6）
- Q6 ✅ `create_workspace` 自动 adopt 已有外部 worktree（四级查找第 3 级）

**Phase A 第一步硬前置：**
- A0 spike：`mcp__superset__create_workspace({branchName: "test"})` 返回的 worktree path 是否 = 我们 `.worktrees/<branch>/` 约定。不一致 → 改路径约定（影响面大）

**关键文件改动估算：**
- 新建：`scripts/scan-task-done.sh`、`.claude/hooks/task-done-check.sh`、6-9 条 `tests/v3_T*.sh`
- 改动：`skills/task-confirm/SKILL.md` 步骤 5、`skills/task-execute/SKILL.md`、`templates/CLAUDE.md.tmpl` 角色表、`templates/settings.json.tmpl`
- 删除（vs v3）：`codex-bg.sh`、`/task-abort` skill、PGID 树杀、mutex、boot epoch、max_parallel

**下次接任者要知道:**
- 读 `设计-Superset独立Claude执行.md`，重点 §2 决策快照 + §8 实现顺序 + §10 v3 复用矩阵
- v3 plan (`设计-并行任务执行.md`) 已 deprecated 但保留作章节复用源
- A0 spike 必须先做（验证 Superset `resolveWorktreePath` 与我们路径约定一致性）

---

## v3 (DEPRECATED 2026-04-25): 取消 Suborchestrator subagent，Map-Reduce 并行执行架构

**🚨 已被 v3.5（Superset MCP 方案）取代。** 文档保留作章节复用源（事件流 / scan-task-done / wakeup / hook 边界）和决策溯源。如果未来要做并行，G1-G15 加固清单和 T1-T11 测试可在 v3.5 上叠加。

详 `设计-并行任务执行.md` 顶部 deprecated banner。

---

### v3 原文（保留供历史溯源）

**What:** 从"每个 task spawn 一个 Claude Agent subagent 做 suborchestrator"改成"主 Orchestrator 直接承担 + 并行后台执行 worker"。

具体机制：
- `/task-confirm` 不再调 `Agent(subagent_type=...)` spawn subagent。直接用 `nohup` / `setsid` 起一个**独立后台 bash 进程**跑 executor（codex / cursor-agent）
- 后台进程自包含：跑 executor → 写 `.runs/task-NNN.done.json`（exit_code / elapsed / log_path）→ 自行退出
- 主 Orchestrator（主会话）用 `ScheduleWakeup`（dynamic 模式，15-20 分钟）周期扫 `.runs/` 下的 done sentinel
- 发现完成的 task → 主会话进入该 task worktree，跑 `/review`、转状态、通知 PM
- 同时**多个 task 并行启动**：每个一个独立后台进程，互不阻塞。主会话收口串行（但后处理 < 1 分钟，不是瓶颈）
- 加 `UserPromptSubmit` hook 作兜底——PM 早于 wakeup 输入时，hook 先扫 sentinel 并在消息前注入待处理 task 列表
- 加 `max_parallel_tasks` 软配置（默认 3-5），超过提示 PM 确认

**角色表调整**：Suborchestrator 作为独立 Claude 角色**消失**。CLAUDE.md 角色表改成：
- 主 Orchestrator：流程推进 + task 启动 + 完成后收口
- 后台 worker（非 Claude 角色，是 bash/codex 进程）：纯干活，写 sentinel 就退

**Why:** 当前架构的机制级错误——`Agent(subagent_type=...)` 是**一次性短命 subagent**（跑完 prompt → return → 回收），但 suborchestrator 的职责是**长跑协调**（等 codex 10-30 分钟 → 写日志 → 跑 /review → 转状态）。Claude Bash 工具 10 分钟 timeout + codex high reasoning 10-30 分钟 → subagent 被迫 `run_in_background=true` + Monitor → turn 结束就退出 → codex 还在跑但"项目经理"下班了。这不是代码 bug，是把"项目经理"岗位雇了"临时工"——机制选错。

并行需求让**方向 A（主会话直接接管但串行）**也被排除——单线主会话没法同时跑 3-5 个 codex。必须把"耗时执行"和"收口协调"拆开：前者并行（多进程），后者串行但快（主会话）。

**Pros:**
- 支持并行：PM 一次同意 3-5 个 task 一起推，codex 实际并发跑，总时间 ≈ 单 task 耗时 + 收口串行尾巴
- 用 Claude Code 原生机制（`run_in_background`、`ScheduleWakeup`、hook），不造新概念
- 主会话永不阻塞：fire-and-forget 启动 + 轮询模型
- hook 兜底让 PM 早回来也能立即处理完成的 task，不用等 wakeup
- Subagent 机制仍在合适场景保留（analysis-reviewer、探索型查询等短任务），只是不再误用

**Cons:**
- **改动面大**：`skills/task-confirm` 删 Spawn Subagent；`skills/task-execute` 改"启动即返回"；新增 `scripts/exec-adapters/*-bg.sh`；新增 `scripts/scan-task-done.sh` / `scripts/process-task-done.sh`；新增 `hooks/task-done-check.sh` + settings.json 注册；`templates/CLAUDE.md.tmpl` 角色表重写；`templates/task.md.tmpl` 文案调整；`skills/task-status` 扩展展示后台运行中 task
- **和 v2 正面冲突**：v2 要求"同时只能有一个 worktree 处于可写（serial 约束）"；v3 要求"并行多个 worktree 可写"。两个方向不能同时落地，需要先对齐架构 north star
- 主会话 context 随并行数增长（每个 task 的收口要读日志 / 跑 review），并发过高会撑爆
- `ScheduleWakeup` 每轮都消耗一次模型调用（即便 no-op），成本要算
- 并行度限制是软约束——AI 可能为了"帮 PM 省事"一次启 10 个 task，需要强制 cap
- 后台进程如果崩了且没写 sentinel，hook/wakeup 永远发现不了——需要 liveness 检查（pid 存活 + 超时阈值）

**Context（2026-04-24 事件）:**
- admin console4 req-001 task-001 执行时触发：/task-confirm spawn 了 suborch subagent；subagent 用 Bash 工具调 codex adapter；Bash 10 分钟超时 → 改 `run_in_background=true` → 用 Monitor 等通知 → subagent turn 结束被回收退出
- codex 进程（PID 57630）仍活着继续跑，但没有 Claude 进程监控它
- PM 那边的 AI 检查到这个现象，推断是"suborch subagent 过早退出是个框架问题"并上报
- PM 提出"未来要做并行"，方向 A（主会话独占）直接被否决

**Status (2026-04-25):** 🟡 **Plan 收敛完成，实施暂停往后放**。设计文档 `设计-并行任务执行.md` 已可作为 Phase A 输入，但 PM 决定先不动手。Phase A kickoff 时按 §10.1 TODO-A1~A11 逐条跑，无需重新讨论方向。

**Depends on / blocked by:**
- ~~north star 抉择~~ ✅ **2026-04-24 PM 选 (a) 并行优先**（v2 降级），尽管 /autoplan 6 路声音反对
- ~~`ScheduleWakeup` 在业务项目里是否可用~~ ✅ **2026-04-24 POC 通过**（见 `设计-并行任务执行.md` §9.1）
- ~~Q3 task_timeout 阈值~~ ✅ 10/30，详 §10 Q3
- ~~Q5 ScheduleWakeup 频率~~ ✅ adaptive 5/20，详 §10 Q5 + §2.6
- ~~Q6 subagent 使用边界文档~~ ✅ 已落 templates/CLAUDE.md.tmpl
- **未解决**：3 个 codex 并发的 token 成本和主机资源开销仍需实跑测
- **未解决**：hook 在 Linux/WSL 的稳定性（macOS 已验证）
- **未解决**：admin console4 实际迁移动作（runtime 兜底已加，执行时机由 PM 定）
- **加固硬约束**：实施中必须落地 G1-G15 共 15 条加固（见 `设计-并行任务执行.md` §11），覆盖 /autoplan + plan-eng-review 全部 critical issues
- **测试硬约束**：Phase A 完工前 T1-T11 必须全绿（§11.5）

**下次接任者要知道:**
- **从哪里恢复**：读 `设计-并行任务执行.md`，重点 §10.1 (Phase A todo) + §11 G1-G15 + §11.5 T1-T11。无需重新评审 north star/Q3/Q5/Q6
- 当前 suborch spawn 在 `skills/task-confirm/SKILL.md` 步骤 5（v3 启动后由 TODO-A7 重写）
- 当前 codex adapter 在 `scripts/exec-adapters/codex.sh`，**同步阻塞**模式（v3 后并存 codex-bg.sh）
- Suborchestrator 的"项目经理"职责在 v1/v2 里是抽象角色——实现绑到 subagent 上只是当前选择，取消它不会伤害"职责"本身，只是换载体
- 完成信号已决定：合并到 `.runs/events/<task>.jsonl` 单一事件流，**不**建 `.done.json` / `.processed`（事件类型 `execution_completed_bg` / `execution_failed_bg` / `execution_crashed_bg` / `execution_aborted` / `reduced_bg`）
- Subagent 机制本身在别处还要用（`analysis-reviewer` 等），不要把 subagent 当问题——问题是"拿 subagent 当长跑 orchestrator"这个具体误用；规则已落 templates/CLAUDE.md.tmpl
- PM 提到"并行"指的可能只是"一次同意多个 task 让它们在后台跑"，不是"多 Claude 实例"——确认 use case 再动手
- 和 v2 的架构抉择是动手前的**硬前置**，不要在未定 north star 的情况下先写 v3 代码（已定 v3 优先，v2 降级）
- **Plan 阶段刻意不创建的文件**：`/task-abort` skill / `codex-bg.sh` / `scan-task-done.sh` / hook / 11 条 v3_T*.sh 测试 —— 全部登记在 §10.1 TODO，开工时按表执行
