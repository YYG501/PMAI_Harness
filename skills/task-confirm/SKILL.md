---
name: task-confirm
description: |
  PM 确认启动一个 task：展示摘要、校验依赖、创建 worktree，并输出新窗口启动指令。
---

# /task-confirm

## When To Use

- PM 调用，参数是 task **PM 视图主文件**路径（如 `/task-confirm tasks/task-001-login-ui.md`）
- 工程合同（`tasks/task-001-login-ui.engineering.md`）由 task-spec 同时生成，与主文件成对

## 拆两文件约定（必读）

本 skill 处理拆两文件的 task 产物（`_shared/PM-VIEW-RULES.md` §二）：
- **PM 视图主文件**（`.md`）：PM 决策、功能清单、范围、验收清单 — 本 skill 主要读取与展示对象
- **工程合同**（`.engineering.md`）：实现细节、易错点、plan-review 沉淀、启动前必读 — 本 skill 仅做"成对存在"校验，不解析内容

confirm 阶段**强校验**：两文件必须成对存在；缺工程合同 = error，提示 PM 先回 `/task-spec` 重新生成。

## Preamble

```bash
source "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/scripts/skill-preamble.sh"
echo "SKILL: task-confirm"
```

## Workflow

### 步骤 1：读取 task 文件（成对校验）

1. 读取 PM 指定的**主文件**（PM 视图，`.md`），从「📌 任务卡」+「✅ 验收清单」+「📦 范围」提取关键信息（用于步骤 2 摘要）。

2. **成对存在校验**：检查同目录同 slug 的 `<task-file-stem>.engineering.md` 是否存在。
   - **存在**（PR 2 之后生成的新 task 应有此文件）→ 后续 executor / model / 审查工具字段从工程合同 §1 读取
   - **不存在**（兼容 PR 1 之前的旧格式 task）→ 输出 warning 并按单文件兼容模式继续：
     ```bash
     ENG_FILE="${TASK_FILE%.md}.engineering.md"
     if [ ! -f "$ENG_FILE" ]; then
       echo "⚠️  工程合同缺失（旧格式 task，按单文件兼容模式继续）：$ENG_FILE"
       HAS_ENG=false
     else
       HAS_ENG=true
     fi
     ```
     兼容模式下从主文件 (`$TASK_FILE`) 读取 executor / model 字段（旧模板这些字段在主文件顶部）。

### 步骤 1.4：行数 lint（v2 文档输出深度指引硬约束）

工程合同存在时（`HAS_ENG=true`），跑 lint 校验 `.engineering.md` 行数：

```bash
python3 .claude/scripts/check-engineering-doc-size.py "$ENG_FILE"
```

- **退出 0** → 进步骤 1.5；
- **退出 1（超限）** → 给 PM 选项：

  ```
  ⚠️ <task-file-stem>.engineering.md 超过原型档行数上限（实测 N 行 / 上限 200 行）
  超限通常意味着工程合同重抄了 PM 视图内容（参见 lint 输出的修法）。

  A) 回 /task-spec 让 AI 裁剪重写超限段落（推荐——按强制引用规则）
  B) PM 自己改文件后回 /task-confirm
  C) 接受超限，强制推进（请说明理由，记到 `[OVERRIDE-DOCSIZE]` 注释里）

  请选 A / B / C：
  ```

  - PM 选 A → 让 PM 在主窗口调 /task-spec（revise 模式）让 AI 裁剪 → 改完后重跑 /task-confirm
  - PM 选 B → 等 PM 改完，回 /task-confirm
  - PM 选 C → 在 `<engineering-file>` 末尾追加 `<!-- OVERRIDE-DOCSIZE: <YYYY-MM-DD> reason: <PM 理由> -->`，进步骤 1.5

**档位非 prototype**：lint 自动跳过（v2 §五.4 决策）；步骤 1.4 直接通过到 1.5。

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

推荐 review-input bundle 命令（PM 在主窗口跑，把 .runs/* 路径喂给 gstack review skill）:
  python3 .claude/scripts/build-review-input.py <task-file> --review design
  python3 .claude/scripts/build-review-input.py <task-file> --review eng
  python3 .claude/scripts/build-review-input.py <task-file> --review dx
（bundle 派生 PM 视图 + 工程视图相关章节 + 项目级文档；review 输出沉淀按 source anchor 路由回源文件）
```

`<task-file>` 用 task PM 视图主文件路径（相对当前 req worktree）。bundle 写到 `.runs/review-input-<task>-<review>.md`。详细约定见 `skills/_shared/REVIEW-INPUT-BUNDLE.md`。

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

> **双向 commit 行为说明（task-002 实证 / 22146458 case）**：sed 改完 task md 字段后，task-confirm 实际会产生**两个孪生 commit**（差几秒）：
> - `task-NNN: switch executor to <X> (per PM at task-confirm)` — 在 **task 分支**
> - `task-NNN: switch executor to <X> (sync from task-confirm)` — 在 **req 分支**
>
> 这两个 commit 都是元信息（仅改 executor / executor_model / 开发服务器 / port 字段，不改 src/ 代码）。它们的时间戳会早于事件流首次 `*→执行中` 事件（因为 task-execute 此时还没启动）。
>
> close-task.sh 的 I-CT8 audit 通过 `commit_only_touches_task_docs()`（A1 hotfix，见 `scripts/audit-task-events.py`）豁免它们：commit 改动文件全部是 `task-NNN.md` / `task-NNN.engineering.md` → skip I-CT8 时间戳检查。Phase 2（A2）落地后改用 commit subject prefix 豁免，本节描述会同步更新。

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

脚本输出两行：第一行是 worktree 路径，第二行是端口号。

**v4.5 行为**：脚本 fork task 分支后**自动把 task md（PM 视图主文件 + 工程合同）从 req 分支删除并 commit**——task md 在 task 分支独家所有，避免 v4 时代两份共存导致的路径解析赌博。close-task 时 merge 会自动"认回" task md 进入 req 分支作为最终历史档案。

更新 task 文件（**注意：在 task worktree 内的副本里改，不在 req 分支**）：
- `**worktree：**` → worktree 路径
- `**开发服务器：**` → `http://localhost:<port>`

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
