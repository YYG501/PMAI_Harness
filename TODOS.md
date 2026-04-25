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

## v4: PM 手动开新窗口执行 task（并行原生）

**Status (2026-04-25):** 🟢 **Plan 收敛完成 + 并行优先决议**，未实施。详见 `设计-PM手动新窗口执行.md`。

**What:** `/task-confirm` 不调任何 MCP / 不 spawn 任何东西，**只输出极简启动指令给 PM**。PM 在新窗口启 Claude → 输 `/task-execute`（无参数自动找唯一待启动 task；多候选时显式参数）→ SKILL 自动 cd worktree + 转执行中 + 跑 codex + 走 v1 现有 /task-submit。PM 跑完回主窗口任意输入触发 preamble 扫描自动呈交"待验收"。**支持并行**：PM 想多 task 同时跑就开多个新窗口，每窗口独立 Claude 实例，git worktree 天然隔离。

**Why:**
- 解决 v1 subagent 短命载体问题（2026-04-22 / 2026-04-24 事件根因）
- 极简：协调责任还给 PM 大脑，AI 不自动协调多进程
- 并行复杂度归零：无 reducer / 无 mutex / 无 hook / 无 sentinel / 无 PGID 树杀（v3 plan 担心的全部消失）
- IDE-agnostic 完全本地（不依赖 Superset MCP / SaaS）
- 改动量约 4-5 文件 + 1 invariant 修改

**关键决策:**
- D0 ✅ **并行原生**（PM 决定开几个新窗口）
- D1 ❌ 不依赖 Superset MCP / IDE 接口
- D2 task-confirm 不转状态；task-execute 转
- D3 完成检测靠 PM 主动告知 + preamble 顺手扫
- D4 中止：PM 关窗口 + 回主告诉
- D5 不调 ScheduleWakeup
- D6 task-execute 无参数自动找唯一；多候选显式参数
- D7 **放宽 I-TT2**：同 req 多 task 同时执行允许

**关键文件改动估算:**
- 改：`skills/task-confirm/SKILL.md`（步骤 5 改输出 echo + 不转状态 + 多候选检测）
- 改：`skills/task-execute/SKILL.md`（无参数模式 + 自动 cd worktree + 入口 transition）
- 改：`skills/task-status/SKILL.md`（多 task 摘要 + "待验收"/"待启动"提示）
- 改：`templates/CLAUDE.md.tmpl`（角色表 + 工作流文案 + 并行说明）
- 改：`scripts/task-transition.py`（删除 check_serial_constraint 或改 no-op，I-TT2 放宽）
- 改：`INVARIANTS.md`（更新 I-TT2 描述）
- 新建：~5-7 条 `tests/v4_T*.sh`

**Phase A 第一步（A0）：**
- 修 invariant：放宽 I-TT2，单测同 req 多 task 同时执行允许

**v1 现有 bug（不阻塞 v4，但建议修）：**
- FM6 v1 codex 非 0 退出后是否自动调 fail-execution？需查
- FM7 v1 task-transition.py:211 append_event 子进程返回码被忽略 → I-CT7 fail-closed 不彻底
- FM8 v1 命名清理 task_short_id / task_stem

**下次接任者要知道:**
- 读 `设计-PM手动新窗口执行.md`，重点 §3 架构 + §4.1/§4.2 改动 + §11 测试 + §13 风险
- v3.5 plan 已 deprecated，但章节复用源仍有价值（autoplan eng review 13 gap 分析）
- v4 哲学："协调责任还给 PM 大脑，AI 不自动协调多进程"

---

## v3.5 (DEPRECATED 2026-04-25): Superset MCP 启独立 Claude 执行 task（serial）

**🚨 已被 v4（PM 手动开新窗口 + 并行原生）取代。** 详见 `设计-Superset独立Claude执行.md` 顶部 deprecated banner。

文档保留作章节复用源（autoplan eng review 13 critical/high gap 分析），如果未来又要做"AI 自动启动独立 Claude"方向可作起点。

---

### v3.5 原文（保留供溯源）

**Status (2026-04-25):** 🟢 **Plan 收敛完成**，未实施（已被 v4 取代）。详见 `设计-Superset独立Claude执行.md`。

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
- A0 spike：`mcp__superset__create_workspace({branchName: "test"})` 返回的 worktree path 是否 = 我们 `.worktrees/<branch>/` 约定。不一致 → **不能改 .worktrees 内部约定**（FM9）—— 引入 path adapter 层

**autoplan eng review 待修 high/medium gap（Phase A 启动前必修）：**
- **FM4** stale 检测：scan-task-done 把 `execution_crashed` 改名 `execution_stale`，需要新 Claude 跑 codex 期间每 60s append `heartbeat` 事件，scan 用 `last_heartbeat` 判 stale 而非 elapsed
- **FM6 验证**：plan §4.6 已加 "execution_failed → fail-execution"，但需新增 T(execution_failed → 待确认) 测试
- **FM7 task-transition.py 事务性**：`update_field` 写状态字段成功但 `append_event` 失败时，必须恢复旧状态字段或退出非 0；当前代码忽略 append 子进程返回码（task-transition.py:211），违反 I-CT7 fail-closed
- **FM8 命名清理**：plan 还有少量地方（§3 架构图 / §10 矩阵）混用 task-005 / task-005-superset-integration，需通读
- **FM9 path adapter**：A0 失败分支不要改 `.worktrees/<branch>/` 约定（影响 check-branch / close-task / status-view 全链路），改写"引入 Superset workspace path adapter 保持框架内部不变"
- **FM12 spike**：新 Claude pane 启动后跑 `claude mcp list` 确认 codex / 其他 MCP server 是否真的可用；如果 worktree settings.json 不继承主仓 MCP 配置，需要 task-confirm 启动前 `cp` 一份
- **F9 (subagent) settings 安全**：`superset.device_id` / `project_id` 放 `.claude/settings.local.json`（gitignored）不要 commit；plan §5.2 settings.json.tmpl 改对应位置
- **F14 (subagent) 多项目 device_id 冲突**：scan-task-done 输出含 `workspaceId` 帮 PM 区分多 pane；`/task-status` 显示 superset workspace pane title 提示
- **F15 (subagent) 命名 cosmetic**：settings 字段从 `parallel_tasks.*` 重命名 `task_execution.*`（D0 是 serial）

**autoplan eng review 新增测试（Phase A 完工前必绿）：**
- T15 task-confirm 5a/5b/5c/5d 任一失败的 rollback（fail-execution 调用 + worktree/workspace 状态）
- T16 双 reducer 单 reduced 事件（wakeup + hook 同秒触发，flock 互斥验证）
- T17 scan-task-done 解析真实 task-events.py 产出（schema 兼容回归）
- T18 task_short_id vs task_stem 主键一致性
- T19 stale heartbeat recovery（FM4 落地后）
- T20 close-task archives superset workspace mapping（FM10 + §7.7）
- T21 A0 mismatch 不破坏 .worktrees 内部 layout（FM9）

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

---

## DX backlog (来自 plan-devex-review 2026-04-25)

来源：`设计-stage5-6-task循环.md` 的 plan-devex-review 产出。这些 friction 不在该 plan scope 内，作为后续独立改进点。

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
- **UP**：现有 v1 项目（ExampleConsumerB 等）升级到 stage 5/6 重设计 v2 的完整路径
  - sync skills/templates 脚本
  - 进行中 req 按当前 stage 提供继续路径
  - 旧 module 规格 lazy migration（doc-update 时自动 reorganize）
  - **依赖**：本 plan（设计-stage5-6-task循环.md）实施完毕；ExampleConsumerB req-001 有阶段性结论后再启动

---

## Eng backlog (来自 plan-eng-review 2026-04-25)

来源：`设计-stage5-6-task循环.md` 的 plan-eng-review 产出。本 plan scope 外，作为后续改进点。

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
