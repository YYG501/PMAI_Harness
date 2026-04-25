---
name: task-confirm
description: |
  PM 确认启动一个 task：展示摘要、校验依赖、创建 worktree，并输出新窗口启动指令。
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

### 步骤 4-pre：依赖前置检查（v4 主防线）

在创建 worktree 之前，必须先检查 task 文件的 `## 依赖` section：

1. 解析 `## 依赖` section，只提取 `task-NNN` 模式的结构化依赖 ID。
2. 在同一个 req 的 task 目录中，为每个依赖 ID 查找对应 `task-NNN-*.md`。
3. 读取每个依赖 task 的状态。
4. 任一依赖状态不是「已完成」时：
   - `exit 1`
   - 主窗口直接报错给 PM：
     ```text
     ❌ task-NNN 依赖未完成：task-MMM 当前状态为「<status>」。
     请先 close 依赖 task，再重新运行 /task-confirm <task-file>。
     ```
   - 不创建 worktree，不修改 task 状态。
5. 全部依赖均为「已完成」时，通过检查，继续步骤 4。

依赖解析规则：

```bash
# 仅机器解析 task-NNN；"无" 或空 section 表示无依赖。
DEPENDENCIES=$(awk '
  /^## 依赖/{flag=1; next}
  /^## / && flag{flag=0}
  flag{print}
' "<task-file>" | grep -Eo 'task-[0-9]{3}' | sort -u)
```

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

### 步骤 5：输出新窗口启动指令（v4 单窗口 lifecycle）

`/task-confirm` 只负责确认、依赖 gate 和创建 worktree；不启动 agent，不调用 `task-transition.py`。task 状态保持「待确认」，直到 PM 在新窗口运行 `/task-execute` 后由入口前置逻辑转换为「执行中」。

检测 `PENDING_COUNT`：

- 范围：主仓 active req 下所有状态为「待确认」且 worktree 已建的 task。
- 计数依据：task 文件状态为「待确认」，且 `.worktrees/<task-stem>` 已存在。

输出规则：

```text
已创建 task worktree：<task-worktree>
Task 状态保持「待确认」。
```

- `PENDING_COUNT <= 1` 时，提示 PM 在新窗口进入 worktree 后运行：
  ```text
  /task-execute
  ```

- `PENDING_COUNT > 1` 时，必须显式带短 ID，避免新窗口误选：
  ```text
  /task-execute task-NNN
  ```

中止流程：

```text
如果决定放弃：关闭新窗口，回主窗口告诉我「放弃 task-NNN」。
状态仍为「待确认」，未进入执行阶段。
```

### 步骤 6：给 PM 可复制命令输出

```
已准备 Task-<id>，执行方式：<EXECUTOR>[ / <MODEL>]

下一步：
  1. 打开新窗口，进入 <task-worktree>
  2. 运行上方给出的 /task-execute 命令
  3. /task-status 查看所有 task
```

## Rules

- 必须在 req worktree 中执行（WORKTREE_TYPE 应为 req）
- task 文件路径如果是相对路径，基于当前 req worktree 解析
- 状态转换必须通过 task-transition.py，不能手动改状态字段
- /task-confirm 不转换为「执行中」；转换发生在 /task-execute 入口前置
