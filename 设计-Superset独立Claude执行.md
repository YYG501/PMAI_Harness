# 设计：Superset MCP 启独立 Claude 执行 task

> **状态**：2026-04-25 PM 决议方案；plan 已收敛，**未实施**。
> **取代**：`设计-并行任务执行.md`（v3 并行方案，已 deprecated；少量章节被本方案复用）。
> **不并行**：当前方案 serial 单线，多 task 不同时跑。未来若要并行，可在本方案上叠加 `max_parallel` 配额（v3 plan 的并行加固清单 G5/G6/G14 仍然适用）。

## 0. 一句话方案

`/task-confirm` 通过 Superset MCP `start_agent_session_with_prompt` 启动一个**独立持久 Claude Code 终端 pane**，cwd 绑定 task worktree，新 Claude 自己同步跑 codex（`Bash run_in_background` + `Monitor`，方向 A 模式）。完成时 append 事件到 `.runs/events/<task>.jsonl`。主 Claude 用 `ScheduleWakeup` adaptive + `UserPromptSubmit` hook 扫事件流收口（review、状态转换、通知 PM）。

---

## 1. Context

### 1.1 触发：subagent 载体根因

2026-04-22 / 2026-04-24 两次事件：`/task-confirm` spawn `Agent(subagent_type=...)` 子进程跑 task；subagent 用 `Bash(run_in_background=true)` 启 codex；codex 跑 10-30 min，但 subagent turn 结束就被框架回收——**项目经理下班，工人还在加班**，没人收口。

根因不是 subagent 有 bug，是**载体误用**：subagent 设计上就是短命的（独立 context、跑完即退、便于并行隔离查询），把"长跑协调"职责塞给它就坏。

### 1.2 候选方案对比

| 方案 | 载体 | 改动 | PM 体验 | 风险 |
|---|---|---|---|---|
| 现状 v1 | subagent | 0 | codex 孤儿（已发生 2 次） | 不可接受 |
| v3 并行 | nohup setsid 后台进程 + ScheduleWakeup + hook | 巨大（20+ 文件） | 主窗口不阻塞 + 多 task 并行 | 改动面爆炸；并行复杂度（mutex / boot epoch / PGID 树杀）|
| 方向 A | 主会话 Bash run_in_background + Monitor 阻塞 | 极小（3 文件）| 主窗口被独占 | Monitor 长阻塞未实测 |
| **本方案 B** | **Superset MCP 启独立 Claude 终端 pane** | 中等（5-7 文件）| 主窗口释放 + 新窗口可视化 | 依赖 Superset SaaS；C2 layout 兼容性 spike 待做 |

PM 选 B：**比方向 A 多了"独立 Claude 项目经理"载体，比 v3 砍掉 60% 改动**。

### 1.3 与 v3 plan 的关系

本方案**复用** v3 plan 的事件流 / scan-task-done / adaptive wakeup / hook 边界这部分设计——它们和"载体是 nohup setsid 还是独立 Claude"无关。**删除** v3 plan 的并行控制部分（mutex、boot epoch、PGID 树杀、`/task-abort`、max_parallel）——serial 单线用不上。详见 §10 复用/删除矩阵。

---

## 2. 决策快照

| ID | 决策点 | 答案 | 来源 |
|---|---|---|---|
| D0 | 是否并行 | ❌ 否，serial 单线（暂时）| 2026-04-25 PM |
| D1 | Superset SaaS 隐私边界 | ✅ 接受；MCP 经过 SaaS 的只有 workspaceId / prompt / agent 类型，task 内容/代码 diff/codex 输出全在本地 | 2026-04-25 PM |
| D2 | Worktree 复用策略 | **B：保留 `create-task-worktree.sh`，Superset 通过 adoption 路径接管已有 worktree** | 2026-04-25 PM |
| Q1 | Superset session 是持久 REPL 还是一次性 | ✅ 持久——`claude --permission-mode acceptEdits` 在 desktop 终端 pane 跑 | agent 查源码 `builtin-terminal-agents.ts:65`|
| Q2 | session cwd 控制 | cwd 自动 = workspace 的 worktree 路径；env vars **不能直接传**，靠 prompt 前缀 `export X=Y &&` | agent 查源码 `shared.ts:47-73` |
| Q3 | 完成通知 | ❌ 无 sessionId / 无 webhook / 无 get_session_status；MCP 返回的是"启动 ack"。**必须自建 sentinel/事件流**| agent 查源码 `tools/utils/utils.ts:33-145` |
| Q6 | `create_workspace` 能否 adopt 已有 worktree | ✅ 可——四级查找的第 3 级 `createWorkspaceFromExternalWorktree` 自动 adoption；adopt 后返回标准 `workspaceId` | agent 查源码 `apps/desktop/.../create.ts:444-454` |
| C1 | `/task-confirm` 多一次 `create_workspace(branchName)` MCP 调用 | 已接受 | Q6 caveat |
| C2 | Worktree 路径必须等于 `resolveWorktreePath(project, branch)`，否则 "multiple candidates" 报错 | ⚠️ **未验证；Phase A 第一步 spike** | Q6 caveat |
| C3 | branch 是 join key，1 branch 多 worktree 会 adoption 死锁 | ✅ v1 已经 1 branch 1 worktree，无影响 | Q6 caveat |

---

## 3. 新架构概览

```
PM ─[/task-confirm task-005]─▶ 主 Claude（在 req worktree）
                                   │
                                   │ 1. create-task-worktree.sh（已有脚本）
                                   │    └─▶ .worktrees/task-005-<slug>/  ← git worktree 创建
                                   │
                                   │ 2. mcp__superset__create_workspace({
                                   │      branchName: "task-005-<slug>"
                                   │    })
                                   │    └─▶ Superset adopt（不重建 worktree），返回 workspaceId
                                   │
                                   │ 3. mcp__superset__start_agent_session_with_prompt({
                                   │      agent: "claude",
                                   │      workspaceId: <adopt 返回的 ID>,
                                   │      prompt: "export PM_AI_TASK=task-005 && /task-execute task-005"
                                   │    })
                                   │    └─▶ 新终端 pane 启动持久 Claude
                                   │        cwd = .worktrees/task-005-<slug>/
                                   │
                                   │ 4. 主 Claude ScheduleWakeup(300, "扫 task-005 完成事件")
                                   ▼
                              主 Claude turn 结束（PM 可继续主窗口聊别的）

新终端 pane（独立 Claude 实例）
   │
   │ /task-execute task-005
   │   └─▶ 读 task 文件、build prompt
   │   └─▶ Bash(codex.sh, run_in_background=true) → shell_id
   │   └─▶ Monitor(shell_id, until=进程退出) ← 同步等
   │   └─▶ 跑完调 task-events.py append execution_completed
   │   └─▶ 自跑 /review、自审记录、转待验收
   │   └─▶ 通知 PM "task-005 待验收"（终端打印 + 可选系统通知）
   │   └─▶ 新 Claude 退出（PM 关 pane 或自动 exit）
   ▼
.runs/events/task-005.jsonl 出现 execution_completed 事件

主 Claude（adaptive wakeup 触发，或 PM 输入 UserPromptSubmit hook 触发）
   │
   │ scan-task-done.sh
   │   └─▶ 扫 .runs/events/*.jsonl，发现 task-005 completed
   │   └─▶ 主 Claude 接续：在主窗口里向 PM 呈交"task-005 待验收，差异 X，请确认"
```

**关键差异 vs v3 plan**：
- 新 Claude 实例**自跑** `/review` + 转 `待验收`，主 Claude 只负责"通知 PM 验收 / PM 决定后转 `已完成`"。这把主 Claude 的收口工作量降到最低
- 不需要 `codex-bg.sh`——新 Claude 自己同步跑 codex（方向 A 模式），它是独立进程不会被回收
- 不需要 `/task-abort` PGID 树杀——PM 直接关掉新 Claude 的终端 pane 即可中止

---

## 4. 组件详细设计

### 4.1 `skills/task-confirm/SKILL.md` 步骤 5 重写

旧（v1）：spawn Agent subagent。
新：调 3 个 MCP 工具串行。

**伪代码**：

```
# 步骤 5：启动独立 Claude 执行 task
TASK_ID="task-005"
BRANCH_NAME="task-005-<slug>"  # 与 git branch 一致
WORKTREE_PATH=".worktrees/${BRANCH_NAME}"

# 5a. 调 create-task-worktree.sh（v1 现有脚本，无需改）
bash .claude/scripts/create-task-worktree.sh "$TASK_ID"

# 5b. 注册到 Superset（adoption 路径）
WORKSPACE_RESULT=$(mcp__superset__create_workspace({
  deviceId: <从 list_devices 拿>,
  projectId: <从 list_projects 拿>,
  workspaces: [{ branchName: BRANCH_NAME }]
}))
WORKSPACE_ID=$(echo "$WORKSPACE_RESULT" | jq -r '.workspaces[0].id')

# 5c. 启动新 Claude 终端
mcp__superset__start_agent_session_with_prompt({
  deviceId: <同上>,
  workspaceId: WORKSPACE_ID,
  agent: "claude",
  prompt: "export PM_AI_TASK=${TASK_ID} && /task-execute ${TASK_ID}"
})

# 5d. 排程 wakeup 收口
ScheduleWakeup(300, prompt="扫 .runs/events/ 看 ${TASK_ID} 是否完成", reason="adaptive fast 首轮")
```

**前置检查**（在 5a 之前）：
- `mcp__superset__*` 工具可用（MCP server 已配置）
- `list_devices` 和 `list_projects` 能拿到值（PM 在 Superset 里有注册项目）
- 本机 `claude` CLI 可调用（Superset 启的 session 会调本机 claude）

**失败 fallback**（任一 5b/5c 失败）：
- 5b 失败 → 拒绝启动，提示 PM 检查 Superset 配置
- 5c 失败但 5b 成功 → 删除 Superset workspace 记录（避免下次 adoption 冲突），提示 PM
- 不允许"半启动"状态——5a/5b/5c 必须事务性，否则回滚

### 4.2 完成事件格式（复用 v3 §2.2）

`.runs/events/<task>.jsonl` 单一事件流，新增以下事件类型（vs v3 命名略调整去掉 `_bg` 后缀，因为不再是后台进程是独立 Claude）：

| 事件类型 | 写入方 | 含义 |
|---|---|---|
| `execution_started` | 新 Claude（步骤 4 入口） | task-execute 开始执行 |
| `execution_completed` | 新 Claude（codex 退出 0）| codex 跑完成功，准备 review |
| `execution_failed` | 新 Claude（codex 非 0 退出）| 包含 exit_code、stderr 摘要 |
| `execution_crashed` | scan-task-done 推断 | 新 Claude 进程死了但没写 completed/failed（Superset workspace 状态变 idle 但事件流无 completion）|
| `review_completed` | 新 Claude 跑完 /review 后 | review 输出摘要 |
| `status_changed` | task-transition.py | 已有，无变化 |
| `reduced` | scan-task-done | 主 Claude 完成收口（向 PM 呈交） |

**事件追加用 `task-events.py append`**（已有脚本），G13 硬约束（jq -n --arg 不用 heredoc）。

### 4.3 `scripts/scan-task-done.sh`（复用 v3 §2.4，简化）

主 Claude / hook 入口共用。

**v3 vs 本方案差异**：
- ❌ 删除 G5 flock mutex（serial 单线，无并发 reduce 风险）
- ❌ 删除 G6 PID + boot epoch 三元组（不再追踪进程 PID，进程在 Superset 终端里 PM 看得见）
- ❌ 删除 PGID 树杀逻辑（不需要 `/task-abort`）
- ✅ 保留 adaptive wakeup `NEXT_WAKEUP_SECONDS` 输出（任一活跃 task elapsed < warn → fast；都 ≥ warn → slow）
- ✅ 保留 overtime warn / kill 分支（warn = OVERTIME_WARN 事件 + PM 文案；kill = 通过 Superset MCP `delete_workspace` 或 PM 手动关 pane）

**简化伪代码**：

```bash
#!/usr/bin/env bash
set -euo pipefail
MAIN_REPO_ROOT="${MAIN_REPO_ROOT:?required}"
cd "$MAIN_REPO_ROOT"

ACTIVE_TASKS=$(find requirements/active -name 'task-*.md' \
  -exec grep -l '^状态: 执行中$' {} \;)

MIN_ELAPSED=999999
ANY_ACTIVE=0

for task_file in $ACTIVE_TASKS; do
  TASK_ID=$(basename "$task_file" .md)
  EVENT_FILE=".runs/events/${TASK_ID}.jsonl"
  [ -f "$EVENT_FILE" ] || continue

  STARTED_AT=$(jq -r 'select(.event=="execution_started") | .ts' "$EVENT_FILE" | head -1)
  COMPLETED=$(jq -r 'select(.event=="execution_completed" or .event=="execution_failed") | .event' "$EVENT_FILE" | head -1)
  REDUCED=$(jq -r 'select(.event=="reduced") | .event' "$EVENT_FILE" | head -1)

  if [ -n "$COMPLETED" ] && [ -z "$REDUCED" ]; then
    # 主 Claude 接续这个 task 的收口
    echo "REDUCE_NEEDED: $TASK_ID ($COMPLETED)"
    ANY_ACTIVE=1
    continue
  fi

  if [ -n "$STARTED_AT" ] && [ -z "$COMPLETED" ]; then
    NOW=$(date +%s)
    ELAPSED=$(( NOW - $(date -d "$STARTED_AT" +%s) ))
    [ "$ELAPSED" -lt "$MIN_ELAPSED" ] && MIN_ELAPSED="$ELAPSED"
    ANY_ACTIVE=1

    # overtime warn
    WARN_MIN=$(jq -r '.parallel_tasks.task_timeout_warn_minutes // 10' .claude/settings.json 2>/dev/null || echo 10)
    KILL_MIN=$(jq -r '.parallel_tasks.task_timeout_kill_minutes // 30' .claude/settings.json 2>/dev/null || echo 30)
    if [ "$ELAPSED" -ge "$((WARN_MIN * 60))" ]; then
      ALREADY_WARNED=$(jq -r 'select(.event=="timeout_warned") | .event' "$EVENT_FILE" | head -1)
      [ -z "$ALREADY_WARNED" ] && python3 .claude/scripts/task-events.py append "$TASK_ID" timeout_warned --field elapsed=$ELAPSED
    fi
    if [ "$ELAPSED" -ge "$((KILL_MIN * 60))" ]; then
      echo "TIMEOUT_KILL_NEEDED: $TASK_ID elapsed=${ELAPSED}s"
      # 这里不直接 kill——主 Claude 看到这个 sentinel 后调 mcp__superset__delete_workspace 或提示 PM
    fi
  fi
done

# adaptive 下次 wakeup 周期
if [ "$ANY_ACTIVE" -eq 1 ]; then
  FAST_MIN=$(jq -r '.parallel_tasks.wakeup_adaptive_fast_minutes // 5' .claude/settings.json 2>/dev/null || echo 5)
  SLOW_MIN=$(jq -r '.parallel_tasks.wakeup_adaptive_slow_minutes // 20' .claude/settings.json 2>/dev/null || echo 20)
  WARN_MIN=$(jq -r '.parallel_tasks.task_timeout_warn_minutes // 10' .claude/settings.json 2>/dev/null || echo 10)
  if [ "$MIN_ELAPSED" -lt "$((WARN_MIN * 60))" ]; then
    echo "NEXT_WAKEUP_SECONDS: $((FAST_MIN * 60))"
  else
    echo "NEXT_WAKEUP_SECONDS: $((SLOW_MIN * 60))"
  fi
fi
```

主 Claude 读这个脚本输出，根据 `REDUCE_NEEDED` / `TIMEOUT_KILL_NEEDED` / `NEXT_WAKEUP_SECONDS` 行决定下一动作。

### 4.4 `UserPromptSubmit` hook（复用 v3 §2.5）

PM 在主窗口输入消息时，hook 在 Claude 处理前先扫一次 `.runs/events/`，把"待收口 task 列表"prepend 到 PM 消息里。让 Claude 先决定"先回答 PM 还是先收口"。

**关键约束（G7 项目边界）**：hook 必须先检查 `.pm-ai-workflow/project.json` 或类似标记文件，确认当前 cwd 是生成器产出的项目，否则立即 exit 0。**避免任何带 `.runs/` 的仓库被污染**。

### 4.5 ScheduleWakeup adaptive（复用 v3 §2.6）

- `wakeup_adaptive_fast_minutes = 5`（任一活跃 task `elapsed < warn`）
- `wakeup_adaptive_slow_minutes = 20`（所有活跃 task `elapsed >= warn`）
- `/task-confirm` 启动 task 后强制 `ScheduleWakeup(300)` 覆盖前一次排程（依赖 G15 覆盖语义）

### 4.6 失败 / 超时

| 场景 | 处理 |
|---|---|
| 新 Claude 终端 pane 崩溃（PM 关了 / 系统崩） | 事件流无 completion → scan-task-done 推断 `execution_crashed` → 主 Claude 提示 PM "task-X 进程消失，是否重启" |
| Codex timeout 超过 kill 阈值 | scan-task-done 输出 `TIMEOUT_KILL_NEEDED` → 主 Claude 调 `mcp__superset__delete_workspace` 或提示 PM 手动关 pane → 写 `execution_aborted{by:"timeout"}` 事件 |
| Superset MCP 不可用（断网 / token 失效） | `/task-confirm` 拒绝启动；提示 PM 修复后重试。**不允许 fallback 到旧 subagent 流程**——避免悄悄回到旧 bug |
| Superset adoption 冲突（C2 multiple candidates）| `/task-confirm` 立即报错并删除已创建的 git worktree（5a 回滚），提示 PM 清理同 branch 多 worktree 的状态 |

---

## 5. 数据结构

### 5.1 `.runs/` 目录

| 文件 | 用途 | 写入方 |
|---|---|---|
| `.runs/events/<task>.jsonl` | 单一事件流（complete/failed/crashed/started/reviewed/aborted/timeout_warned/reduced） | 新 Claude / scan-task-done / task-transition |
| `.runs/superset/<task>.workspace.json` | 记录 task → superset workspaceId 映射，便于后续 delete_workspace | task-confirm 步骤 5b 后写 |

不需要：v3 plan 的 `.runs/<task>.pid`（无后台进程要追踪）。

### 5.2 `settings.json` 新配置

```json
{
  "parallel_tasks": {
    "task_timeout_warn_minutes": 10,
    "task_timeout_kill_minutes": 30,
    "wakeup_adaptive_fast_minutes": 5,
    "wakeup_adaptive_slow_minutes": 20
  },
  "superset": {
    "device_id": "<PM 的 Superset device UUID>",
    "project_id": "<PM 的 Superset project UUID>",
    "default_agent": "claude"
  }
}
```

不需要：v3 的 `max_parallel`（serial 单线）。

### 5.3 task 文件 frontmatter

无变化。

---

## 6. 各 skill 改动

### 6.1 `skills/task-confirm/SKILL.md`

**步骤 5 重写**（详 §4.1）：删 spawn subagent，改调 3 个 MCP 工具。
**前置增加**：检查 superset MCP 可用性 + settings.json 里 `superset.device_id` / `project_id` 已配置。

### 6.2 `skills/task-execute/SKILL.md`

**改动较少**：原本是被 subagent 调用的入口，现在是被独立 Claude 调用。
- 删掉"假设我是 subagent"的措辞
- 加一段"我是独立 Claude，跑完后调 task-events append execution_completed，然后自跑 /review，转待验收"
- codex 调用方式不变（`Bash run_in_background + Monitor`）

### 6.3 `skills/task-status/SKILL.md`

**新增展示**：哪些 task 在跑（从 `.runs/events/` 推断 + Superset workspace 状态查询可选）；显示 superset workspace pane 提示，方便 PM 切过去看。

### 6.4 `templates/CLAUDE.md.tmpl` 角色表

**重写第 18 行**：
- 旧：`Suborchestrator | 单 task owner：preflight、实现、自审、收口 | task worktree`
- 新：`独立执行 Claude | 单 task owner，由 Superset MCP 启动；preflight、实现、自审、转待验收 | task worktree（终端 pane）`

`Subagent 使用边界` 段已落地（2026-04-25 commit `24df0f3`），无需重写。

---

## 7. 失败 fallback

### 7.1 Superset MCP 不可用

`/task-confirm` 拒绝启动，提示 PM。**不允许 fallback 到旧 subagent 流程**。

### 7.2 新 Claude 进程死了但事件流无 completion

scan-task-done 检测：last 事件是 `execution_started` 但超过 kill 阈值仍无 completed/failed → 写 `execution_crashed` → 主 Claude 提示 PM。

### 7.3 主 Claude 关闭

主 Claude 关闭后无人 reduce。下次 PM 启动 Claude Code，`UserPromptSubmit` hook 立即扫 `.runs/events/` 把待收口列表注入第一条消息，主 Claude 立刻处理。

### 7.4 ScheduleWakeup 不触发 / 覆盖语义异常

G15 hard precondition：Phase A 测试 T11 验证。失败则改为"显式 cancel 后重排"或 idempotent 令牌。

### 7.5 存量业务项目资产缺失

业务项目（admin console4）已有 v1 安装。Phase A 上线后业务项目要手动同步：`.claude/scripts/`、`.claude/hooks/`、`templates/`、settings.json 新增段。task-confirm 启动前检查 `mcp__superset__*` 工具是否注册，缺则 hard fail 提示 PM 升级。

### 7.6 Codex 超时

详 §4.6 表。

---

## 8. 实现顺序（north star 已定，本节是 Phase A 步骤）

| Phase | 内容 | 验收 |
|---|---|---|
| **A0 spike** | C2 worktree layout 兼容性验证：跑一次 `mcp__superset__create_workspace({branchName: "test-branch"})`，看返回的 workspace 实际指向哪个 path；和我们 `.worktrees/<branch>/` 比对 | 路径一致 → 进 A1；不一致 → 改 `create-task-worktree.sh` 路径约定，影响面评估 |
| A1 | `task-confirm` 步骤 5 重写 + settings.json 加 `superset.*` 段 | 单元测试：mock MCP 工具，验证 5a/5b/5c 串行 + 失败回滚 |
| A2 | `task-execute` 改文案 + 新 Claude 自跑 `/review` 流程 | 手工测试：用 Superset 启 session 跑一个简单 task |
| A3 | `scan-task-done.sh` 简化版（去 mutex / boot epoch / PGID） | T1 / T9 / T10 / T11 通过 |
| A4 | `UserPromptSubmit` hook（带 G7 项目边界） | T4 通过 |
| A5 | `templates/CLAUDE.md.tmpl` 角色表重写 | 手工 review |
| A6 | 测试套（精简至 6-7 条，详 §11） | 全绿 |
| A7 | 业务项目升级（admin console4） | 业务项目能成功跑 `/task-confirm` |

---

## 9. 暂不做

- 多 task 并行（D0 决议；未来要做时叠加 max_parallel + G5/G6/G14）
- `/task-abort` skill（PM 直接关 Superset terminal pane 即可中止）
- Superset task / project 与我们 task md 双向同步（除非 PM 真的要在 Superset UI 看 task 进度）
- 跨 IDE 兼容性（PM 使用什么 IDE 就用什么 Superset 客户端）

---

## 10. v3 plan 复用 / 删除矩阵

| v3 plan 段落 | 本方案处理 | 原因 |
|---|---|---|
| §2.1 后台 worker `codex-bg.sh` | ❌ **删除** | 新 Claude 自己同步跑 codex，无需后台进程 |
| §2.2 完成事件格式 | ✅ **复用**（§4.2，命名去 `_bg`） | 事件流和载体无关 |
| §2.3 主 Orchestrator 启动多 task | 🟡 **重写** | 改成调 Superset MCP，不用 nohup |
| §2.4 scan-task-done | 🟡 **复用 + 简化**（§4.3） | 删 mutex / boot epoch / PGID |
| §2.5 UserPromptSubmit hook | ✅ **复用**（§4.4） | hook 边界 G7 仍适用 |
| §2.6 ScheduleWakeup adaptive | ✅ **复用**（§4.5） | adaptive 5/20 不变 |
| §2.7 `/task-abort` | ❌ **删除** | PM 直接关 pane |
| §3.1 `.runs/` 目录 | 🟡 **简化** | 去掉 `.pid`，加 `.workspace.json` |
| §3.2 settings.json | 🟡 **简化** | 去 `max_parallel`，加 `superset.*` |
| §6 失败 fallback | ✅ **复用** | F5 / F6 / F7 大部分仍适用 |
| §10.1 Phase A todo | 🟡 **重写**（§8） | TODO-A1~A11 重新组织 |
| §11 G1-G15 加固清单 | 🟡 **取舍**：保留 G4 / G7 / G12 / G13 / G15；删 G1（POC 已过）/ G2 / G3 / G5 / G6 / G14（并行控制） | 见下表 |
| §11.5 T1-T11 测试 | 🟡 **取舍**：保留 T1 / T4 / T5 / T7 / T9 / T11；删 T2 / T3 / T6 / T8 / T10（并行 / abort） | 见下表 |

### 加固清单（保留）

| # | 加固 | 仍然适用的原因 |
|---|---|---|
| G4 | Shell injection 防御（executor 白名单 / task-id regex / jq -n --arg）| 任何 shell 拼接场景都要防 |
| G7 | UserPromptSubmit hook 项目边界 | hook 仍存在 |
| G12 | umask 077 + `.runs/` chmod 700 | 日志泄漏防御 |
| G13 | shell 实现硬约束（jq -n --arg / `${BASH_SOURCE[0]%/*}` / trap rm tmp / `PM_AI_TASK` env） | 通用 |
| G15 | ScheduleWakeup 覆盖语义 | adaptive wakeup 用到 |

### 测试清单（保留 + 新增）

| # | 测试 | 反例 |
|---|---|---|
| T1 | 事件追加原子性 | append 中途 SIGKILL / 磁盘满 |
| T4 | hook 项目边界 | 在非 PM-AI-Workflow 项目 cwd 跑 hook |
| T5 | task-id regex 防注入 | 恶意 task 文件名 |
| T7 | 越界写入检测（adapter 后置校验） | 跑 task 时 prompt 引导写别 task worktree |
| T9 | ScheduleWakeup 实延触发 | 排 900s |
| T11 | adaptive 周期切换 + 覆盖语义 | fast→slow 切换 + 二次调用覆盖 |
| **T12（新增）** | Superset adoption 路径 | `create-task-worktree.sh` 创建 worktree 后调 `create_workspace`，验证返回的 workspaceId 指向 adopt 路径而不是新建 |
| **T13（新增）** | Superset session 启动 → cwd 验证 | 启 session 后 `pwd` 输出 = `.worktrees/<task>/` |
| **T14（新增）** | Superset MCP 不可用时 task-confirm 拒绝启动 | 网络断 / token 失效 → task-confirm exit 1，不创建半启动状态 |

---

## 11. 待实测点

| # | 测试目标 | 状态 |
|---|---|---|
| 1 | Q1：Claude session 持久 REPL 行为（不会因 Superset 重启而被回收） | 🟡 源码证据强，未实测 |
| 2 | C2：worktree 路径与 Superset `resolveWorktreePath` 一致性 | ❌ **必须 A0 spike** |
| 3 | Q3 workaround：scan-task-done sentinel 兜底完整性 | 🟡 设计明确，待 T1 / T13 |
| 4 | Superset SaaS round-trip 内容审计（确认只传 workspaceId / prompt / agent，不传 task 文件） | 🟡 D1 已接受，但执行时建议抓一次 MCP 流量验证 |
| 5 | env vars `export PM_AI_TASK=...` 前缀方案是否被新 Claude 看到 | 🟡 hack 方案，A2 第一步验证 |
| 6 | adaptive wakeup `NEXT_WAKEUP_SECONDS` 输出能否被主 Claude 正确解析并调 ScheduleWakeup | 🟡 T11 覆盖 |

---

## 12. 开放问题

（决策已基本清空，下列是 PM 在 Phase A 启动前最后确认）

1. **PM 用的 Superset 客户端是什么版本** —— 影响 MCP 工具列表完整性（不同版本可能 tool schema 略不同）
2. **业务项目 admin console4 何时升级** —— 现有 task 跑残的处理（PM 决定时机）
3. **A0 spike 由谁跑** —— 需要 PM 在 Superset 桌面端真实跑一次 `create_workspace`，看返回 path

---

## 13. 决策溯源

| 时间 | 事件 | 输出 |
|---|---|---|
| 2026-04-22 | task-005 worktree 内混入 task-001~004 代码 | 引出 v2 worktree 物化方案（已搁置）+ 加 I-CT7/I-CT8 事件流审计 |
| 2026-04-24 | admin console4 task-001 suborch subagent 退出 codex 孤儿 | 引出 v3 并行方案 |
| 2026-04-24 | /autoplan 6 路评审 | 12 条 G1-G12 加固清单；6 路反对 v3 方向但 PM 选 (a) |
| 2026-04-24 | /plan-eng-review | 5 条增量修订（事件流合一 / G13 G14 G15 / T11 / §10.1 Phase A todo） |
| 2026-04-25 | PM 决定 v3 暂停 | TODOS 标 🟡 plan-complete + paused |
| 2026-04-25 | PM 提"独立 IDE Claude 实例"思路 | 方向 B 出现 |
| 2026-04-25 | agent 查 Superset MCP 源码（Q1-Q3 / Q6） | 方向 B 可行性确认 |
| 2026-04-25 | PM 决定 D1 / D2-B / Q6 spike | 本文档诞生 |

---

## 附录：核心文件影响清单

**新建**：
- `scripts/scan-task-done.sh`（本方案 §4.3 简化版，~80 行）
- `.claude/hooks/task-done-check.sh`（§4.4）
- `tests/v3_T01_event_append.sh`、`v3_T04_hook_boundary.sh`、`v3_T05_taskid_regex.sh`、`v3_T07_diff_scope.sh`、`v3_T09_wakeup_delay.sh`、`v3_T11_adaptive_overwrite.sh`、`v3_T12_superset_adoption.sh`、`v3_T13_superset_cwd.sh`、`v3_T14_mcp_unavailable.sh`

**改动**：
- `skills/task-confirm/SKILL.md`（步骤 5 重写）
- `skills/task-execute/SKILL.md`（文案 + 自跑 review）
- `skills/task-status/SKILL.md`（新增展示）
- `templates/CLAUDE.md.tmpl`（角色表第 18 行）
- `templates/settings.json.tmpl`（新增 `superset.*` 段）
- `tests/run-all.sh`（追加新测试）
- `INVARIANTS.md`（视情况追加 Superset 相关不变式）

**保留不变**：
- `scripts/exec-adapters/codex.sh`（codex 调用方式不变；同步阻塞模式由调用方控制）
- `scripts/exec-adapters/_gate.sh`（I-AD1 / I-AD2 仍适用）
- `scripts/task-transition.py` / `req-transition.py`（无并行 → 不需要扩展 I-TT1 abort 路径）
- `scripts/create-task-worktree.sh`（worktree 由我们脚本管，Superset adoption）
- `scripts/close-task.sh` / `close-req.sh`（无影响）

**删除**（vs v3 plan）：
- 不创建 `scripts/exec-adapters/codex-bg.sh`
- 不创建 `skills/task-abort/`
- 不创建 `scripts/task-abort.sh`
