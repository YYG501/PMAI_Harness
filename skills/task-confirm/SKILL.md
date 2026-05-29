---
name: pmai-task-confirm
description: |
  机器步骤（AI 后台自动跑，PM 不感知）：build 期间 task 定稿后，自动 fork 一份 task 工作副本（隔离环境）+ 校验依赖，让该 task 的 demo 在干净环境里建。PM 正常流程下不直接调；窗口被关 / context 丢失时可手动 /pmai-task-confirm <task 文件> 作恢复入口。
---

# /pmai-task-confirm

> **角色（六步重构后）**：task-confirm 是 build 这一步内部的**机器步骤**——AI 后台自动跑，PM 完全不感知。它不出 PM 视图 banner、不出"切窗口"提示、不设任何确认门。唯一可见路径是**异常恢复**：PM 的 task 窗口被关 / context 丢失 / 隔离副本没建成时，PM 手动 `/pmai-task-confirm <task 文件>` 让 AI 重新把环境补齐。
>
> **PM 视图**：正常后台流程下本 skill 不打 banner、不输出"开新窗口"那一类提示（这些已从 PM 视图隐藏；PM 在同一条 build 推进里继续看 demo，不被工程动作打断）。仅恢复入口允许出一行轻量过场告诉 PM 在补环境。banner 格式真相源仍是 `_shared/pm-view/banner-rules.md`，本 skill 后台态不触发其中任何门。
>
> **PM 答题规则（M4）**：本 skill 后台态不向 PM 提问（全是机械流程，没有 AskUserQuestion 门）。恢复入口若需 PM 输入，按 `_shared/pm-view/askuser-rules.md` §1 四条硬规则走（空答 STOP / 没拿到答案禁止落盘 fork / runtime 退化保留 wait）。

## When To Use

- **正常路径（PM 不感知）**：build 期间，`/pmai-task-spec` 把单个 task 定稿落盘后**续跑触发**本 skill（见下「task-spec 续跑」）——AI 在后台自动 fork 工作副本 + 校验依赖，PM 不需要、也不应该手动贴 `/pmai-task-confirm <path>`。
- **恢复入口（PM 手动）**：task 工作环境没建成 / 窗口被关 / context 丢失时，PM 手动 `/pmai-task-confirm tasks/task-001-login-ui.md` 让 AI 重新补齐隔离副本。这是兜底逃生路径，不是常规入口。

**task-spec 续跑**：task-spec 把 task 文件 commit 到 req 分支后，**不让 PM 手动贴命令**，直接在同一 chat 内续跑本 skill 的 workflow（机械流程，无确认门，PM 不需重敲）。续跑路径行为与恢复入口手动调完全一致。

## task 文件形态

task-spec 产 **单文件 typed contract**（`tasks/task-NNN-<slug>.md`，头部带
`<!-- task_format: single-typed-v3 -->` 标记，内部分 PM 确认区 / 执行区 / 审计区）。
本 skill 只读机器需要的字段（依赖、executor、worktree、dev server），不向 PM 复述摘要——
摘要展示是 PM 视图的事，本 skill 后台态不打扰 PM。

> **task-confirm = 纯机器流程**：PM 在整个 task 生命周期里看 demo 拍方向的确认点不在这里。
> task-confirm **不设任何确认门** —— 它只做：依赖 gate（机器校验）+ 自动 fork 工作副本 +
> 回填环境字段。全程后台，无 PM 决策。

**三态兼容**：仓里同时有 3 种 task 格式 —— v3 新单文件（有 task_format 标记）/ v2 旧双文件
（有 `.engineering.md`）/ v1 老单文件。用 `python3 "$PMAI_HOME/scripts/_lib/state.py" detect_format
<task-file>` 判别。v2 双文件保留兼容读路径；v3 缺 `.engineering.md` 是正常、不报告警。

## Preamble

```bash
source "$HOME/.pmai/scripts/skill-preamble.sh"
echo "SKILL: task-confirm"
# 后台态：不打 PM 视图 banner（角色见顶部说明）。恢复入口若 PM 需要锚点可加，
# 但正常 build 推进里 task-confirm 静默，不打断 PM 看 demo 的节奏。
```

## Workflow

> 以下全部在 AI 后台自动执行。任一步出错 → 停下，把错误原文转给 PM（用 PM 听得懂的话），
> 提示可手动 `/pmai-task-confirm <task 文件>` 恢复。

### 步骤 1：读取 task 文件

读取 task 文件，提取机器需要的字段（依赖、executor / executor_model、worktree、dev server）。
后台态**不**向 PM 复述任务卡 / 验收清单摘要。

**格式判别**（三态兼容）：

```bash
FMT=$(python3 "$PMAI_HOME/scripts/_lib/state.py" detect_format "$TASK_FILE")
# v3 = 新单文件 typed contract（正常态，无 .engineering.md 是正常）
# v2 = 旧双文件 task（在飞旧 task）→ 兼容模式继续，不向 PM 报告警
# v1 = 老单文件
```

v3 缺 `.engineering.md` 是正常 —— **不报告警**。v2 时静默走兼容读路径。

### 步骤 1.5：plan review 状态（机器记录，不阻塞）

可选：调 `task-events.py check-plan-reviews <task-file>` 拿推荐 / 已跑 / 未跑列表，仅作机器记录。脚本永远 exit 0，缺 review 不阻止 fork（I-RV2，撤销旧 hard gate）。后台态不向 PM 复述；PM 想跑 review 是体验迭代阶段的事，由 `/pmai-next` 推进里处理，不在本机器步骤打断。

### 步骤 2：解析 executor + model（机器内部）

```bash
RESOLVED=$(python3 "$PMAI_HOME/scripts/resolve-executor.py" "<task-file>")
EXECUTOR=$(echo "$RESOLVED" | jq -r .executor)
MODEL=$(echo "$RESOLVED" | jq -r '.model // ""')
```

executor / model 是机器内部解析结果，**mode 中立**——后台直接采用 task 文件里的值，
不向 PM 列"4 个可选执行方式"那一类菜单（执行方式是栈内的事，PM 不感知）。
PM 若在体验迭代里主动说"换 codex"，由 `/pmai-next` 推进流程处理，不是本机器步骤的职责。

> **commit 行为说明**：如果因恢复入口需要 sed 改 task 文件字段（executor / executor_model /
> dev server / port），会产生元信息 commit（不改 src/ 代码）。close-task 的 I-CT8 audit
> 通过 `commit_only_touches_task_docs`（见 `scripts/audit-task-events.py`）豁免：commit
> 改动文件全部是 task 文件 → skip I-CT8 时间戳检查。

### 步骤 3：依赖前置检查（机器防线）

在 fork 工作副本之前，必须先检查 task 文件的 `## 依赖` section：

1. 解析 `## 依赖` section，只提取 `task-NNN` 模式的结构化依赖 ID。
2. 在同一个 req 的 task 目录中，为每个依赖 ID 查找对应 `task-NNN-*.md`。
3. 读取每个依赖 task 的状态。
4. 任一依赖状态不是「已完成」时：
   - `exit 1`，不 fork、不改 task 状态。
   - 停下来把这件事用 PM 听得懂的话讲清楚（哪个 task 还没收口、当前是什么状态、需要先收口它再回来）。
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

### 步骤 4：fork task 工作副本（若未存在）

从 `.req-meta.json` 读取 req 分支名，检测工作副本未存在时自动 fork（恢复 / 重试场景已存在则跳过）：

```bash
if [ ! -d "<expected-worktree-path>" ]; then
  bash "$PMAI_HOME/scripts/create-task-worktree.sh" "<task-file>" "<req-branch>"
fi
```

脚本输出两行：第一行是工作副本路径，第二行是端口号。

**行为**：脚本 fork task 分支后**自动把 task 文件从 req 分支删除并 commit**——task 文件
在 task 分支独家所有，避免两份共存导致的路径解析赌博。close-task 时 merge 会自动"认回"
task 文件进入 req 分支作为最终历史档案。（v3 单文件只删一个文件；在飞旧 v2
双文件 task 仍删两个。）

**I-DC1 pre-fork gate**：`create-task-worktree.sh` 在 fork 之前会先检查 req 分支 working tree
里本 task 文件是否 dirty——dirty 时**自动 commit** 后再 fork（pathspec 只覆盖本 task 文件，
不卷入其他改动）。这是兜底防线；正常情况 task-spec 续跑前应已把 task 文件落盘到 req
分支，gate 触发说明续跑流程被绕过或失败。脚本 stderr 输出 "⚠️ I-DC1 pre-fork gate"
警告时，AI 必须把警告原文转给 PM 看一句话说明。

回填环境字段（**注意：在 task 工作副本里改，不在 req 分支**）：
- 「📌 任务卡」表格的 `worktree` → 工作副本路径
- 「📌 任务卡」表格的 `dev server` → `http://localhost:<port>`

> 这两个字段的回填通常推迟到 task-execute 启动时由 agent 写，避免本机器步骤在 task 分支多出"代码先于状态机"的 commit 触发 I-CT8。

### 步骤 5：环境就绪，回到 build 推进（不切窗口、不出 Next Up）

`/pmai-task-confirm` 只负责依赖 gate + fork 工作副本；不启动 agent，不调用 `task-transition.py`。task 状态保持「待执行」，由 build 推进流程接力执行。

**关键差异（六步重构后）**：

- 后台态**不**输出"开新终端窗口 / `claude --add-dir` / 复制 `/pmai-task-execute`"那一类提示——这些工程动作已从 PM 视图隐藏。PM 在同一条 `/pmai-next` build 推进里继续看 demo，不被切窗口打断。
- 工作副本就绪后，控制权交回 build 推进：由 `/pmai-next` 接力进入 task 执行（建这个 task 的 demo），跑完进 build 三道审。task 是"PM 看 demo 确认方向"的阶段单元——PM 感知的是 demo，不是 worktree / 窗口。
- **恢复入口例外**：PM 手动调本 skill 补环境时，可出一行轻量过场告诉 PM 环境已补好、回 `/pmai-next` 继续，不展开工程细节。

> **隔离副本是栈内机制，对 PM 透明**：fork task 工作副本是为了让每个 task 的 demo 在干净环境里建、互不踩踏，这是 build 栈内的事，PM 不需要知道路径、不需要切窗口。worktree 自动托管由框架负责，PM 视角只有"在建这个 task 的 demo"。

## Rules

- 必须在 req worktree 中执行（WORKTREE_TYPE 应为 req）；恢复入口同样要求 cwd 在 req worktree
- task 文件路径如果是相对路径，基于当前 req worktree 解析
- 状态转换必须通过 task-transition.py，不能手动改状态字段
- /pmai-task-confirm 不转换为「执行中」；转换发生在 task 执行入口前置
- **后台态不向 PM 输出任何"切窗口 / 开新会话 / 复制命令"提示**——这些已从 PM 视图隐藏；PM 在 `/pmai-next` build 推进里连续看 demo
- **后台态不打 PM 视图 banner、不列执行方式菜单、不复述任务摘要**——本 skill 是机器步骤，PM 不感知
- 依赖 gate / fork 任一出错 → 停下，把原因用 PM 听得懂的话讲清，提示可手动 `/pmai-task-confirm <task 文件>` 恢复
- plan review 是体验迭代阶段 PM 自跑的事（I-RV1/I-RV2），不当 fork gate；步骤 1.5 仅作机器记录
- 推进驱动是 `/pmai-next`（六步推进），不是旧的 req-stage-gate
