---
name: task-confirm
description: |
  PM 确认启动一个 task：展示摘要、校验依赖、创建 worktree，并输出新窗口启动指令。
---

# /task-confirm

> **PM 视图（M2 banner + Decision gate label）**：入口 banner（`status-view.py --banner-only --skill TASK-CONFIRM`）；退出 Next Up 块引导新窗口 `/task-execute <task-id>`；执行前确认闸门 label 按 `_shared/pm-view/banner-rules.md` §3 3 硬规则（label=动作如「启动 task-NNN」/ description=一句话）。
>
> **PM 答题规则（M4）**：所有 AskUserQuestion 调用按 `_shared/pm-view/askuser-rules.md` §1 3 硬规则走（空答 STOP / 没拿到答案禁止落盘 worktree fork / runtime 退化保留 wait）。

## When To Use

- PM 调用，参数是 task 文件路径（如 `/task-confirm tasks/task-001-login-ui.md`）

## task 文件形态（delta-3）

task-spec 产 **单文件 typed contract**（`tasks/task-NNN-<slug>.md`，头部带
`<!-- task_format: single-typed-v3 -->` 标记，内部分 PM 确认区 / 执行区 / 审计区）。
本 skill 读 PM 确认区的「📌 任务卡」「✅ 验收清单」「📦 范围」做摘要展示。

> **task-confirm = 机械流程**（delta-3 §2.3）：PM 在整个 task 生命周期的唯一确认门已在
> `/task-spec` 步骤 10。task-confirm **不再设自己的「是否确认启动」问句** —— 它只做：
> 摘要展示（informational）+ 可选 executor 切换（非阻塞告知）+ 依赖 gate（机器校验）+
> worktree fork。

**三态兼容**：仓里同时有 3 种 task 格式 —— v3 新单文件（有 task_format 标记）/ v2 旧双文件
（有 `.engineering.md`）/ v1 老单文件。用 `python3 .claude/scripts/_lib/state.py detect_format
<task-file>` 判别。v2 双文件保留兼容读路径；v3 缺 `.engineering.md` 是正常、不报告警。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-confirm"
```

## Workflow

### 步骤 1：读取 task 文件

读取 PM 指定的 task 文件，从 PM 确认区的「📌 任务卡」+「✅ 验收清单」+「📦 范围」提取
关键信息（用于步骤 2 摘要）。executor / executor_model / 审查工具字段在「📌 任务卡」表格里。

**格式判别**（三态兼容）：

```bash
FMT=$(python3 .claude/scripts/_lib/state.py detect_format "$TASK_FILE")
# v3 = 新单文件 typed contract（正常态，无 .engineering.md 是正常）
# v2 = 旧双文件 task（在飞旧 task）→ "检测到旧格式 task（双文件），兼容模式继续"
# v1 = 老单文件
```

v2 时给中性提示（不说「缺失」）：`检测到旧格式 task（双文件），兼容模式继续`。
v3 缺 `.engineering.md` 是正常 —— **不报告警**。

### 步骤 1.5：plan review 推荐摘要（informational，不阻塞）

可选：调 `task-events.py check-plan-reviews <task-file>` 拿到推荐 / 已跑 / 未跑列表，附在步骤 2 摘要里给 PM 看。脚本永远 exit 0，缺 review 不阻止 confirm（I-RV2，撤销旧 I-PR1 hard gate）。如果 PM 想跑，提示回 `/task-spec` 流程或在主窗口手动调 review；跑完贴结论由 AI append `plan_review_completed` 事件。

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
推荐 review 工具（PM 自跑）: /qa, /design-review
plan review: 已跑 X / 未跑 Y（可选信息）
```

review skill（`/qa` / `/design-review` / `/plan-*-review` 等）进入时读 task 单文件全文 +
`docs/DESIGN.md` + 模块规格（参见 `templates/task.md.tmpl` 头部说明）——不需要预派生
bundle、不需要带路径参数，PM 直接 `/qa` 等命令运行即可。

**非默认态展开两行**：

```
执行方式: codex / gpt-5.4 (from settings 默认)
```

### 步骤 3：executor 切换（非阻塞）

> delta-3 §2.3：task-confirm 是机械流程 —— **不设「是否确认启动此 task？」问句**
> （唯一确认门已在 `/task-spec` 步骤 10）。executor 切换是「机械流程 + 一次非阻塞告知」：
> 摘要已在步骤 2 展示当前 executor，步骤 6 输出会列全 4 个可选 executor + 「想换说一声」
> 提示 —— **不阻塞、不专门问**。PM 不响应即用当前 executor 继续。

仅当 PM **主动说**「换 codex / 换 claude-code sonnet」等时才处理：
- 用 sed 就地更新 task 文件「📌 任务卡」表格里的 `executor` / `executor_model` 字段
- 重新调 `resolve-executor.py` 验证（exit 非 0 → 把 stderr 人话错误原样转给 PM，让 PM 改正）
- 重新打印摘要

> **commit 行为说明**：sed 改完 task 文件字段后会产生元信息 commit（仅改 executor /
> executor_model / dev server / port 字段，不改 src/ 代码）。close-task.sh 的 I-CT8 audit
> 通过 `commit_only_touches_task_docs()`（见 `scripts/audit-task-events.py`）豁免：commit
> 改动文件全部是 task 文件 → skip I-CT8 时间戳检查。

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

脚本输出两行：第一行是 worktree 路径，第二行是端口号。

**行为**：脚本 fork task 分支后**自动把 task 文件从 req 分支删除并 commit**——task 文件
在 task 分支独家所有，避免两份共存导致的路径解析赌博。close-task 时 merge 会自动"认回"
task 文件进入 req 分支作为最终历史档案。（delta-3：v3 单文件只删一个文件；在飞旧 v2
双文件 task 仍删两个。）

**I-DC1 pre-fork gate**：`create-task-worktree.sh` 在 fork 之前会先检查 req 分支 working tree
里本 task 文件是否 dirty——dirty 时**自动 commit** 后再 fork（pathspec 只覆盖本 task 文件，
不卷入其他改动）。这是兜底防线；正常情况 task-spec 步骤 11 应已把 task 文件落盘到 req
分支，gate 触发说明 task-spec 流程被绕过或失败。脚本 stderr 输出 "⚠️ I-DC1 pre-fork gate"
警告时，AI 必须把警告原文转给 PM 看一句话说明。

更新 task 文件（**注意：在 task worktree 内的副本里改，不在 req 分支**）：
- 「📌 任务卡」表格的 `worktree` → worktree 路径
- 「📌 任务卡」表格的 `dev server` → `http://localhost:<port>`

> 这两个字段的更新通常推迟到 task-execute 启动时由 agent 回填，避免 task-confirm 阶段在 task 分支多出"代码先于状态机"的 commit 触发 I-CT8。

### 步骤 5：检测 PENDING_COUNT（决定步骤 6 的命令分支）

`/task-confirm` 只负责确认、依赖 gate 和创建 worktree；不启动 agent，不调用 `task-transition.py`。task 状态保持「待执行」，直到 PM 在新窗口运行 `/task-execute` 后由入口前置逻辑转换为「执行中」。

检测 `PENDING_COUNT`：

- 范围：当前 req worktree（task-confirm 必须在 req worktree 里跑，cwd 唯一确定 req）下所有状态为「待执行」且 worktree 已建的 task。
- 计数依据：task 文件状态为「待执行」，且 `.worktrees/<task-stem>` 已存在。

启动模式（关键）：

PM 在新终端窗口里**保持在当前 req worktree 目录**（不进 task worktree），用 `claude --add-dir $MAIN_REPO_ROOT` 启动新 Claude 会话。`--add-dir` 把主仓根加进 Bash 沙盒，让后续 `/task-execute` 入口能持久 cd 进 task worktree。如果不加 `--add-dir`，cd 会被 Claude Code 沙盒 reset，task-execute 失败。

### 步骤 6：给 PM 可复制命令输出

**输出模板**（`$MAIN_REPO_ROOT` 必须展开成 PM 可直接复制的绝对路径；最后 `/task-execute` 那行按 PENDING_COUNT 选一条）：

```
已准备 Task-<id>

📂 worktree
   <TASK_WORKTREE 绝对路径>

🚀 执行方式（当前 ▶ <EXECUTOR>[ / <MODEL>]）
   ▶ <EXECUTOR>[ / <MODEL>]                       ← 当前选这个
     <executor 2> / <默认 model>
     <executor 3> / <默认 model>
     <executor 4>（说明，如 manual = PM 自己写代码）

   想换说一声（例：「换 claude-code sonnet」）；不换就直接看下一步。

▶️ 下一步——开新终端窗口，保持当前 req worktree 目录（别 cd 走）：

   claude --add-dir <主仓根绝对路径>
   /task-execute                  ← PENDING_COUNT == 1
   /task-execute task-<id>        ← PENDING_COUNT > 1（必须带短 ID 避免新窗口误选）

主窗口随时跑 /task-status 看 task 进度。
```

**执行方式列表渲染规则**（必须列全 4 项，按当前 → 其余字母序）：

1. **当前选的那个置顶**，行首 `▶ ` 标记，后面接 `<EXECUTOR> / <MODEL>` 全名
2. **其余 3 个按字母序列出**（`claude-code` → `codex` → `cursor-agent` → `manual` 中除当前外的 3 个）
3. 每个 executor 的展示规则：
   - `claude-code / sonnet`（默认 model = `sonnet`；后括号附`也可换 opus / haiku`只在第一次出现 claude-code 时加）
   - `codex / auto`（默认 `auto`）
   - `cursor-agent / auto`（默认 `auto`）
   - `manual（你自己写代码，task-execute 不派发 agent）`
4. 4 行执行方式块结束后，固定一行**反悔提示**：`想换说一声（例：「换 claude-code sonnet」）；不换就直接看下一步。`

**实际渲染示例**（当前 = `codex / auto`）：

```
🚀 执行方式（当前 ▶ codex / auto）
   ▶ codex / auto
     claude-code / sonnet（也可换 opus / haiku）
     cursor-agent / auto
     manual（你自己写代码，task-execute 不派发 agent）

   想换说一声（例：「换 claude-code sonnet」）；不换就直接看下一步。
```

**模板要点**：
- 标题块用 emoji 锚点（📂 worktree / 🚀 执行方式 / ▶️ 下一步）让 PM 视线快速分段
- worktree 路径独立成段、缩进展示，不再跟"已准备 Task-X"挤同一行
- 执行方式必须**列全**，PM 看到所有可选才能判断要不要换；"想换告诉我"只列一个当前选很难触发 PM 的反悔意识
- `/task-execute` 那行根据 PENDING_COUNT 输出**其中一条**（不要把两条都贴给 PM 让他选；AI 算 PENDING_COUNT 后直接选）
- **不输出**"如果决定放弃……"中止流程——PM 真要放弃直接说「放弃 task-NNN」即可，不在主路径列出避免噪音

## Rules

- 必须在 req worktree 中执行（WORKTREE_TYPE 应为 req）
- task 文件路径如果是相对路径，基于当前 req worktree 解析
- 状态转换必须通过 task-transition.py，不能手动改状态字段
- /task-confirm 不转换为「执行中」；转换发生在 /task-execute 入口前置
- 输出给 PM 的 `claude --add-dir <path>` 必须是展开后的绝对路径（不能是 `$MAIN_REPO_ROOT` 字面量），让 PM 能直接复制粘贴执行
- 步骤 6 输出：执行方式块**必须列全 4 项**（claude-code / codex / cursor-agent / manual），▶ 标当前选，紧跟反悔提示；worktree 路径用 📂 emoji 标段；下一步命令用 ▶️ emoji 标段。不主动列"如果决定放弃……"中止流程，PM 真要放弃直接说「放弃 task-NNN」
- plan review 是 PM 自跑推荐项（I-RV1/I-RV2），不当 confirm gate；步骤 1.5 仅做 informational 摘要
