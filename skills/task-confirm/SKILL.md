---
name: task-confirm
description: |
  PM 确认启动一个 task：展示摘要、创建 worktree、转换状态为执行中。
---

# /task-confirm

## When To Use

- PM 调用，参数是 task 文件路径（如 `/task-confirm tasks/task-001-login-ui.md`）

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-confirm"
```

## Workflow

### 步骤 1：读取 task 文件

读取 PM 指定的 task 文件，提取关键信息。

### 步骤 2：展示 task 摘要（默认压单行，非默认展开）

先解析 executor + model：

```bash
RESOLVED=$(python3 .claude/scripts/resolve-executor.py "<task-file>")
EXECUTOR=$(echo "$RESOLVED" | jq -r .executor)
MODEL=$(echo "$RESOLVED" | jq -r '.model // ""')
SRC_EXEC=$(echo "$RESOLVED" | jq -r .source_executor)
SRC_MODEL=$(echo "$RESOLVED" | jq -r .source_model)
```

**默认态（executor=claude-code 且 model 空）**：

```
Task: task-NNN-<slug>
目标: [任务描述摘要]
验收标准:
  - [ ] 条件 1
  - [ ] 条件 2
依赖: [依赖列表或"无"]
执行方式: claude-code（默认）
审查工具: /qa, /design-review
```

**非默认态展开两行**：

```
执行方式: codex / gpt-5.4 (from settings 默认)
```

### 步骤 3：交互式切换执行者（可选）

询问 PM：

```
是否切换执行方式？（回车保持 <EXECUTOR>）
可选：claude-code / codex / cursor-agent / manual
输入新 executor：
model（留空=用默认，claude-code 仅支持 opus/sonnet/haiku）：
```

如果 PM 输入非空值：
- 用 sed 就地更新 task 文件 `**executor：**` 和 `**executor_model：**` 字段
- 重新调 `resolve-executor.py` 验证（若 exit 非 0，把 stderr 人话错误原样转给 PM，让 PM 改；改正前不继续）
- 重新打印摘要

确认无误后问：`确认启动此 task？（Y/N）`

### 步骤 4：创建 task worktree（若未存在）

从 `.req-meta.json` 读取 req 分支名，检测 worktree 未存在时创建（失败重试场景直接跳过）：

```bash
if [ ! -d "<expected-worktree-path>" ]; then
  bash .claude/scripts/create-task-worktree.sh "<task-file>" "<req-branch>"
fi
```

脚本输出两行：第一行是 worktree 路径，第二行是端口号。更新 task 文件：
- `**worktree：**` → worktree 路径
- `**开发服务器：**` → `http://localhost:<port>`

### 步骤 5：Spawn Suborchestrator（带 model + hard constraint，spawn ack 后才转状态）

**关键：状态保持「待确认」直到 spawn 成功 ack。**

Spawn payload：
- model 参数：若 `EXECUTOR=claude-code` 且 `MODEL` 非空，传给 Agent tool 的 `model` 参数（opus/sonnet/haiku）
- prompt 含：task 文件路径、`resolved_executor`、`resolved_model`、以及 hard constraint：

```
【硬约束】当前 task 的 executor = <EXECUTOR>。当 executor != claude-code 时，
Suborchestrator 只做 orchestration：读 task 文件 + 调 /task-execute 让 dispatch 处理。
禁止直接写业务代码。
```

**spawn 后处理**：

- 若 Agent tool 调用抛错：
  ```bash
  python3 .claude/scripts/task-events.py append "<task-file>" \
    --type suborch_spawn_failed --payload "{\"reason\":\"<error_text>\"}"
  ```
  告知 PM：
  ```
  Suborchestrator 启动失败：<reason>
  状态保持「待确认」，未进入执行阶段。
  可能原因：executor_model=<model> 当前订阅不含、或 Agent tool 暂不可用。
  修复后重跑 /task-confirm。
  ```
  退出 skill，**不转状态**。

- 若 spawn 成功 ack：
  ```bash
  python3 .claude/scripts/task-events.py append "<task-file>" \
    --type suborch_spawn_started --payload "{\"executor\":\"$EXECUTOR\",\"model\":\"$MODEL\"}"
  python3 .claude/scripts/task-transition.py "<task-file>" --to 执行中
  ```

### 步骤 6：给 PM 可复制命令输出

```
已启动 Task-<id>，执行方式：<EXECUTOR>[ / <MODEL>]

下一步（Suborchestrator 正在 <task-worktree> 自动推进）：
  tail -f .runs/execution-task-<id>-<executor>.log  （如需实时看执行日志）
  /task-status                                            （查看所有 task）
```

## Rules

- 必须在 req worktree 中执行（WORKTREE_TYPE 应为 req）
- task 文件路径如果是相对路径，基于当前 req worktree 解析
- 状态转换必须通过 task-transition.py，不能手动改状态字段
- v1 串行模式：同一 req 下只能有一个 task 在执行中或待验收
