# 设计：PM 手动开新窗口执行 task（并行原生）

> **状态**：2026-04-25 PM 决议方案；plan 草稿，**未实施**。
> **取代**：`设计-Superset独立Claude执行.md`（v3.5，已 deprecated）；间接取代 `设计-并行任务执行.md`（v3，已 deprecated）。
> **核心**：极简方向——`/task-confirm` 只输出"启动指令"，PM 自己开新窗口启 Claude 跑 `/task-execute`（无参数自动找）。**支持并行**：PM 想多 task 同时跑就开多个窗口，每个窗口 = 一个独立 Claude 实例，git worktree 天然隔离。无 reducer / 无 hook / 无 sentinel / 无 PGID 树杀——并行复杂度全部由"PM 大脑 + git worktree 隔离"承担，不靠 AI 自动协调。

---

## 0. 一句话方案

PM 开新窗口这件事**让 PM 自己做**，并行也由 PM 决定开几个。AI 只给"如何在新窗口快速开始 task"的方法。

- `/task-confirm` 输出：worktree 已建 + 提示在新窗口启 Claude 跑 `/task-execute`
- PM 自己开新窗口（1 个或 N 个，PM 决定）启 Claude
- 新 Claude 输入 `/task-execute`（**无参数**自动找待启动 task；多候选时显式 `/task-execute <task-file>`）
- SKILL 入口自动 `cd` 到对应 worktree → 转 `执行中` → 跑 codex → 走 v1 现有 `/task-submit` → 转 `待验收`
- PM 跑完关新窗口（或保留），**回主窗口随便说一句** → 主 Claude SKILL preamble 顺手扫 task 状态 → 看到 N 个 `待验收` → 依次呈交 PM 验收

---

## 1. Context

### 1.1 触发：subagent 短命载体根因

2026-04-22 / 2026-04-24 两次事件：subagent turn 结束被回收，codex 长跑变孤儿。**根因**是 subagent 当长跑协调载体用错。

### 1.2 候选方案对比

| 方案 | 载体 | 改动 | PM 体验 | 并行支持 | 主要问题 |
|---|---|---|---|---|---|
| 现状 v1 | subagent | 0 | codex 孤儿（已发生 2 次）| 否 | 不可接受 |
| v3 并行 | nohup setsid + ScheduleWakeup + hook | 巨大（20+ 文件） | 主窗口不阻塞 | AI 自动协调多进程 | 改动面爆炸 + reducer 复杂度 |
| 方向 A | 主会话 Bash run_in_background + Monitor | 极小（3 文件） | 主窗口被独占 | 否 | Monitor 长阻塞未实测 |
| v3.5 (Superset MCP) | Superset 启的独立 Claude pane | 中等（5-7 文件 + 13 critical/high gap） | 主窗口释放 + 可视化 | 否 | 依赖 Superset SaaS；plan 大量待修 |
| **本方案 (v4 PM 手动 + 并行)** | **PM 自己开的窗口** | **极小（4-5 文件）** | **主窗口释放 + PM 完全可见 + 并行原生** | **PM 手动开 N 个窗口** | **PM 多一次切窗口动作；多 task 时认知负担** |

PM 选 v4：**协调责任还给 PM 大脑**，AI 不自动协调多进程。**最干净、最 IDE-agnostic、最不依赖外部服务、并行复杂度归零**。

### 1.3 与 v3.5 plan 的关系

v3.5 plan 大部分章节（事件流 / scan-task-done / wakeup / hook / Superset MCP 集成）**全部消失**——本方案不需要这些机制。
仅 **保留 v1 现有事件流**（`.runs/events/<task-stem>.jsonl`）用于 audit / I-CT7 验证，**不**用作 cross-process 通信。

---

## 2. 决策快照

| ID | 决策点 | 答案 | 来源 |
|---|---|---|---|
| D0 | 是否并行 | ✅ **并行原生** —— PM 决定开几个新窗口，每窗口 = 1 个 task。同 req 多 task 同时执行允许。无 max_parallel 软配额（自然由 PM 手动操作上限决定）| **2026-04-25 PM 选 A** |
| D1 | 是否依赖 Superset MCP / IDE 接口 | ❌ 否——IDE-agnostic，PM 用任何 terminal/IDE 都能跑 | 2026-04-25 PM |
| D2 | 状态转换时机 | **B：`/task-confirm` 不转状态；新窗口里 `/task-execute` SKILL 入口转 `执行中`** | 见 §4.2 |
| D3 | 完成检测机制 | **PM 主动告知**——不是 sentinel 文件、不是 hook、不是 ScheduleWakeup。PM 在新窗口跑完 `/task-submit` 转 `待验收`，回主窗口任意输入触发主 Claude SKILL preamble 顺手扫 | 见 §4.4 |
| D4 | 中止机制 | PM 关新窗口 + 回主窗口说"放弃 task-X"→ 主 Claude 调 `task-transition --fail-execution` | 见 §7.2 |
| D5 | task-confirm 是否调 ScheduleWakeup | ❌ 否——主 Claude 不需要主动唤醒，PM 任意输入都触发 preamble 扫描 | 2026-04-25 PM 简化原则 |
| D6 | task-execute 无参数模式 | ✅ 自动找唯一"待启动"task（status=待确认 + worktree 已建）；多候选时报错列出，PM 显式 `/task-execute <task-file>` | **2026-04-25 PM 简化提议** |
| D7 | I-TT2 invariant | **放宽**——同 req 允许多个 task 处于"执行中"或"待验收"。原 serial 校验删除 | D0 蕴含 |

---

## 3. 新架构概览

```
PM ─[/task-confirm task-005-superset.md]─▶ 主 Claude（在 req worktree）
                                              │
                                              │ 1. 解析 task 文件
                                              │ 2. 前置检查（task 文件存在 / req 分支 / 同 branch worktree 不冲突）
                                              │ 3. bash create-task-worktree.sh <task-file> <req-branch>
                                              │     └─▶ .worktrees/task-005-superset/
                                              │ 4. **不**转状态、**不**调 MCP、**不** spawn subagent
                                              │ 5. 输出启动指令给 PM（详 §4.1）
                                              ▼
                                          主 Claude 完成 turn，等 PM 输入

PM 自己操作（IDE 窗口 / 新 terminal tab / 新 Claude Code 实例 任选）：
   ┌──────────────────────────────────────────────────────┐
   │ cd /<repo>/.worktrees/task-005-superset              │
   │ claude                          # 或 IDE 默认开 Claude  │
   │                                                       │
   │ 在新 Claude 里粘贴：                                   │
   │ /task-execute requirements/active/req-001/tasks/...md│
   └──────────────────────────────────────────────────────┘

新窗口 Claude（独立进程，PM 完全可见）：
   /task-execute
     ├─▶ 入口检查 task 状态 == "待确认"
     ├─▶ task-transition.py --to 执行中（I-TT2 serial 在此校验）
     ├─▶ Bash codex.sh / cursor-agent.sh / manual.sh（同步阻塞）
     ├─▶ 跑完 → 走 v1 现有 /task-submit 流程（自审 + 文档偏差 + review_completed）
     ├─▶ task-transition.py --to 待验收
     └─▶ 提示 "task-X 已转待验收，请回主窗口告诉主 Claude"
   PM 关闭新窗口

PM 回主窗口（任意输入：'task 完成了' / '接下来' / 甚至单纯空消息）：
   主 Claude SKILL preamble 自动跑 status 扫描
     ├─▶ 看到 task-005 状态 == "待验收"
     ├─▶ 拉 diff + 呈交 PM 验收
     └─▶ PM 通过 → /close-task；PM 打回 → /task-transition --to 执行中 + PM 提供反馈
```

**并行场景流（D0 并行原生）**：

```
主窗口 PM 连续 confirm 多个 task：
  PM: /task-confirm task-005   →  worktree-005 已建，提示启动指令
  PM: /task-confirm task-006   →  worktree-006 已建，提示启动指令
  PM: /task-confirm task-007   →  worktree-007 已建，提示启动指令
  现在 3 个 task 状态 "待确认" + 3 个 worktree 已建

PM 决定开几个并行窗口（PM 大脑判断 task 依赖 + 自身认知带宽）：

┌─ 新窗口 A ─────────────┐  ┌─ 新窗口 B ─────────────┐  ┌─ 新窗口 C ─────────────┐
│ claude                 │  │ claude                 │  │ claude                 │
│ /task-execute task-005 │  │ /task-execute task-006 │  │ /task-execute task-007 │
│ (多候选 → 显式参数)      │  │                        │  │                        │
│ → SKILL 自动 cd        │  │ → 自动 cd              │  │ → 自动 cd              │
│ → transition 执行中    │  │ → transition 执行中    │  │ → transition 执行中    │
│ → Bash codex + Monitor │  │ → Bash codex + Monitor │  │ → Bash codex + Monitor │
│ → 跑完 /task-submit    │  │ → 跑完 /task-submit    │  │ → 跑完 /task-submit    │
│ → 转 "待验收"          │  │ → 转 "待验收"          │  │ → 转 "待验收"          │
└────────────────────────┘  └────────────────────────┘  └────────────────────────┘
   git worktree 天然隔离，3 个并发 codex 互不干扰

PM 回主窗口（任意输入）：
   主 Claude preamble 扫到 3 个 "待验收"
   "task-005/006/007 都已转待验收。依次呈交 / 看摘要 / 跳过哪个？"
   PM 一个一个验收 + close（close 顺序由 PM 决定，git merge 处理顺序冲突）
```

**关键差异 vs v3 并行**：
- v3：AI 主动 spawn 后台进程 + ScheduleWakeup poll + hook 兜底 + reducer mutex
- v4：**PM 手动开窗口** + **主 Claude 不主动 reduce**（靠 PM 任意输入触发）+ **无 reducer**
- 并行复杂度归零——多进程协调在 PM 大脑里发生，AI 只负责"PM 一句话能看到当前所有状态"

**关键差异 vs v3.5**：
- 不存在 "新 Claude 是项目经理"——它就是 PM 启的普通 Claude，跑 v1 现有 SKILL
- 主 Claude 不主动收口
- 完全无 cross-process 通信（事件流仅作 audit）
- 无 Superset MCP 集成 / 无 .runs/superset/

---

## 4. 组件详细设计

### 4.1 `skills/task-confirm/SKILL.md` 步骤 5 改输出

**旧（v1）**：spawn Suborchestrator subagent。
**新**：输出极简启动指令 + 不转状态。

伪代码（步骤 5 替换原 spawn 逻辑）：

```bash
# 已经过步骤 1-4：解析 task / 展示摘要 / 切换 executor / 创建 worktree
# 此时 task 状态仍是 "待确认"，worktree 已创建

# 检查是否已有其他 "待启动" task（多候选场景需提示 PM 用显式参数）
PENDING_COUNT=$(find requirements/active -name 'task-*.md' \
  -exec grep -l '^状态：待确认$' {} \; \
  | while read f; do
      stem=$(basename "$f" .md)
      [ -d ".worktrees/$stem" ] && echo "$f"
    done | wc -l | tr -d ' ')

# 输出启动指令（直接 echo 给 PM 看）
if [ "$PENDING_COUNT" -le 1 ]; then
  # 只有这一个待启动 → 新窗口可无参数 /task-execute
  cat <<EOF
✅ Task ${TASK_SHORT_ID} 准备就绪（worktree: .worktrees/${TASK_STEM}）。

请在新窗口启动 Claude（任何方式：新 terminal tab / IDE 新窗口 / 新 Claude Code tab），然后输入：

  /task-execute

新窗口 Claude 会自动找到这个 task 并切到对应 worktree 启动。

执行方式: ${EXECUTOR}${MODEL:+ / $MODEL}

跑完回主窗口随便说一句即可（如 "完成了"），我会自动检测并引导验收。
中止：关新窗口 + 回主告诉我 "放弃 ${TASK_SHORT_ID}"。
EOF
else
  # 已有 N 个待启动 → 新窗口必须显式参数
  cat <<EOF
✅ Task ${TASK_SHORT_ID} 准备就绪（worktree: .worktrees/${TASK_STEM}）。

⚠️ 当前有 ${PENDING_COUNT} 个待启动 task，新窗口必须用显式参数：

  /task-execute ${TASK_FILE_ABS}

执行方式: ${EXECUTOR}${MODEL:+ / $MODEL}

可以**并行开多个新窗口**同时跑不同 task（PM 决定开几个；git worktree 天然隔离）。
跑完回主窗口随便说一句，我会列出所有 "待验收" task 依次呈交。
EOF
fi
```

**前置检查**（步骤 5 之前必须完成）：
- task 文件存在 + 状态 == "待确认"
- req 分支存在
- `git worktree list | grep -q "$TASK_STEM"` 应该为 0（一 branch 一 worktree 强制）
- ⚠️ **不再检查"已有待启动 task"** —— D0 并行允许累积多个待启动

**失败 fallback**：步骤 4 (create-task-worktree.sh) 失败 → 报错给 PM 不输出启动指令；步骤 5 本身只是 echo，不会失败。

**关键**：**步骤 5 不调 task-transition.py**——状态保持 "待确认"，由新窗口的 `/task-execute` 转。这意味着如果 PM 看到指令但没在新窗口跑，task 会一直停在 "待确认"，下次 `/task-status` 会提示。

### 4.2 `skills/task-execute/SKILL.md` 入口加 transition + 无参数模式 + 自动 cd

新窗口 Claude 跑 `/task-execute [<task-file>]`：

```bash
# 步骤 1：定位 task 文件（无参数 → 自动找；有参数 → 用参数）
TASK_FILE="${1:-}"

if [ -z "$TASK_FILE" ]; then
  # D6 无参数模式：扫主仓 active req 找唯一 "待启动" task
  REPO_ROOT=$(git rev-parse --show-toplevel)
  cd "$REPO_ROOT"

  CANDIDATES=$(find requirements/active -name 'task-*.md' \
    -exec grep -l '^状态：待确认$' {} \; \
    | while read f; do
        stem=$(basename "$f" .md)
        [ -d ".worktrees/$stem" ] && echo "$f"
      done)
  COUNT=$(echo "$CANDIDATES" | grep -c .)

  case "$COUNT" in
    0) echo "❌ 没有待启动的 task。请先在主窗口 /task-confirm <task-file>"; exit 1 ;;
    1) TASK_FILE="$CANDIDATES"; echo "自动选定: $TASK_FILE" ;;
    *) echo "⚠️ 有 $COUNT 个待启动 task，请显式参数："
       echo "$CANDIDATES" | sed 's/^/  \/task-execute /'
       exit 1 ;;
  esac
fi

[[ -f "$TASK_FILE" ]] || { echo "task file not found: $TASK_FILE"; exit 1; }
TASK_FILE="$(realpath "$TASK_FILE")"  # 转绝对路径
TASK_STEM="$(basename "$TASK_FILE" .md)"

# 步骤 2：自动 cd 到 task worktree
REPO_ROOT="$(git -C "$(dirname "$TASK_FILE")" rev-parse --show-toplevel 2>/dev/null \
              || git rev-parse --show-toplevel)"
WORKTREE_ABS="$REPO_ROOT/.worktrees/$TASK_STEM"
[ -d "$WORKTREE_ABS" ] || { echo "worktree 不存在：$WORKTREE_ABS"; exit 1; }
cd "$WORKTREE_ABS"
echo "已切换到 worktree: $WORKTREE_ABS"

# 步骤 3：检查状态 + 转 "执行中"
STATUS=$(grep '^状态：' "$TASK_FILE" | awk -F'：' '{print $2}' | xargs)
case "$STATUS" in
  "待确认")
    python3 "$REPO_ROOT/.claude/scripts/task-transition.py" "$TASK_FILE" --to 执行中
    # 注意：D7 放宽 I-TT2 后，同 req 多 task 可同时执行中——transition 不再 serial 拒绝
    ;;
  "执行中")
    echo "task 已在执行中，继续（重试场景）。"
    ;;
  *)
    echo "task 状态是 '$STATUS'，不能 /task-execute。请检查。"
    exit 1
    ;;
esac

# 步骤 4：跑 executor（v1 现有逻辑）
# resolve-executor.py + Bash codex.sh / cursor-agent.sh / manual.sh
# ...

# 步骤 5：跑完后走 v1 现有 /task-submit 流程
# - 提示 PM 填文档偏差 + 自审记录
# - 跑 review (按 task 文件 审查工具 字段 iterate)
# - task-transition.py --to 待验收
# - 提示 "task-X 已转待验收，请回主窗口告诉主 Claude"
```

**关键修订点**：
- D6 **无参数模式**：扫唯一 "待启动" task；多候选时报错列出（PM 显式参数走老路径）
- **自动 cd worktree**：PM 不需要手动 cd，启动 Claude 之后任何位置 `/task-execute` 都能跑
- D7 transition：**I-TT2 放宽**，同 req 多 task 同时执行允许（serial 校验删除）
- I-CB10 (worktree 写入要求状态==执行中) 自然生效
- v1 现状：`/task-execute` 假设是被 subagent 调用 + 状态已经是 "执行中"。新方案改成 SKILL **自己定位 + 自己 cd + 自己转状态**

### 4.3 `skills/task-submit/SKILL.md`（v1 现有，无改动）

PM 在新窗口跑完 `/task-execute`（或 task-execute SKILL 自动接续到 /task-submit），走 v1 现有流程：
- 文档偏差 / 自审记录 / review_completed 事件
- task-transition.py --to 待验收
- 提示 "请回主窗口告诉主 Claude"

### 4.4 主 Claude 收口机制（preamble 顺手扫）

**完全不引入 hook / wakeup / sentinel**。靠 SKILL preamble 已有的 `/task-status` 扫描行为：

PM 在主窗口任意输入 → 主 Claude 处理首条消息前，preamble 跑：
```bash
source .claude/scripts/skill-preamble.sh
# preamble 末尾自动跑 task-status 扫描
```

`task-status` 扫到任何 "待验收" task → 主 Claude 在响应里附加：
> 检测到 task-005 已转 "待验收"。是否要我拉 diff 呈交验收？

PM 同意 → 主 Claude 拉 diff + review report + 呈交 → PM 通过/打回。

**这套机制完全是 v1 现有行为**——不需要新代码。唯一需要确认的：`task-status` SKILL / `skill-preamble.sh` 是否已经能识别"待验收"task 并主动提示？如果没有，加一段提示文案即可（不是新功能）。

### 4.5 中止 task

PM 想中止 → 关新窗口（无副作用，state 仍在 "执行中"）→ 回主窗口说"放弃 task-005" → 主 Claude 调：

```bash
python3 .claude/scripts/task-transition.py "$TASK_FILE" --fail-execution --reason "aborted_by_pm"
```

task 回到 "待确认"，worktree 保留供 PM 检查 dirty diff。**不需要 task-recover.sh / PGID 树杀**——新窗口里的 codex 进程会被 PM 关窗口 + OS 信号自然清理。

---

## 5. 数据结构（基本不变）

### 5.1 `.runs/` 目录（v1 现状不变）

| 文件 | 用途 | 写入方 |
|---|---|---|
| `.runs/events/<task-stem>.jsonl` | 事件流（v1 已有，仅作 audit + I-CT7 验证） | task-transition.py / task-events.py |
| `.runs/<task-stem>.json` | task 运行元数据（v1 已有） | task-execute / 各 adapter |

**不需要**：
- `.runs/superset/<task>.workspace.json`（v3.5 引入，本方案删除）
- `.runs/locks/reducer.lock`（v3.5 引入，本方案删除——无 reducer）
- `.runs/<task>.pid`（v3 引入，本方案删除——无后台进程）
- `.runs/<task>.done.json` sentinel（v3 引入，本方案删除——无 fire-and-forget）

### 5.2 `settings.json`（v1 现状不变）

不引入任何新配置项。删除 v3.5 计划中的 `superset.*` / `parallel_tasks.*` / `task_execution.*`。

### 5.3 task 文件 frontmatter（v1 现状不变）

无变化。

---

## 6. 各 skill 改动总览

| Skill | 改动 |
|---|---|
| `skills/task-confirm/SKILL.md` | **改**：步骤 5 删 spawn subagent，改输出启动指令；步骤 5 不调 task-transition |
| `skills/task-execute/SKILL.md` | **改**：入口加 status check + transition --to 执行中（v1 现状是 task-confirm 转，现在转给 task-execute） |
| `skills/task-submit/SKILL.md` | **不改**（v1 现有逻辑直接复用） |
| `skills/task-status/SKILL.md` | **微改**：扫到 "待确认" 但 worktree 已建的 task，提示 "等待 PM 在新窗口启动"；扫到 "待验收" task 提示 "可呈交验收" |
| `skills/close-task` / `cancel-req` | **不改** |
| `templates/CLAUDE.md.tmpl` 角色表 | **改第 18 行**：`Suborchestrator | 单 task owner ...` → `新窗口 Claude | PM 在新窗口启动的 Claude 实例，跑单 task；位置在 task worktree 里` |
| `templates/CLAUDE.md.tmpl` 工作流文案 | **改**：解释"PM 手动开新窗口"模式，加"中止流程" |

**不动**：
- `scripts/exec-adapters/`（v1 现有 codex.sh / cursor-agent.sh / manual.sh / _gate.sh 全部保留）
- `scripts/create-task-worktree.sh` / `task-transition.py` / `check-branch.sh`（v1 现状全保留）
- `.claude/hooks/`（不引入新 hook）

---

## 7. 失败 fallback

### 7.1 PM 看到启动指令但没在新窗口跑

- task 状态停在 "待确认"，worktree 已建但空
- 下次 PM 在主窗口任意输入，preamble 扫到 → 主 Claude 提示 "task-X 已 confirm 但未启动，需要继续吗？"
- PM 选继续 → 主 Claude 重复输出启动指令；PM 选放弃 → 主 Claude 删 worktree + 状态保持 "待确认"（或 PM 决定 cancel）

### 7.2 PM 在新窗口跑了但中途关窗口

- task 状态停在 "执行中"，I-TT2 serial 阻塞同 req 其他 task
- PM 回主窗口说 "放弃 task-X" → 主 Claude 调 `task-transition --fail-execution --reason aborted_by_pm` → 回 "待确认"
- worktree 保留供 PM 检查 dirty diff（参考 v3.5 §7.6 task-recover 思路，但**不需要新脚本**——直接调 task-transition）

### 7.3 PM 跑完没回主窗口

- task 状态在 "待验收"，无负面影响
- 下次 PM 任意输入主 Claude，preamble 扫到 → 提示验收
- 完全等价于 v1 现状下 PM 走完 /task-submit 不及时回主窗口的场景

### 7.4 PM 在新窗口跑 /task-execute 但状态不是"待确认"

- task-execute SKILL 入口检查到状态异常 → 报错并退出，不调 transition
- 提示 PM 检查（可能是另一个窗口已经启动过 task，或者 task 已经在 "待验收"）

### 7.5 同 branch 多 worktree

- task-confirm 步骤 5 之前的前置检查 `git worktree list` 拦住，不会进步骤 5

### 7.7 并行场景：task 之间代码依赖（D0 新增）

PM 同时 confirm task-005 和 task-006，但 task-006 实现依赖 task-005 已 merge 的代码：
- **PM 责任**：自己判断依赖关系，task-006 等 task-005 close 后再启
- **辅助**：`/task-status` 显示每个 task 的 "依赖：" 字段（v1 现状已支持）；主 Claude 在 task-confirm 时如果检测到 task 文件 "依赖：" 字段非空且依赖 task 还没 close，**警告但不强制阻止**（PM 可能确实想并行启动后手动协调）

### 7.8 并行场景：同一文件不同 task 修改 → merge conflict

- task-005 close 时 merge 到 req 分支成功
- task-006 close 时同一文件已被 task-005 改 → `git merge` 报 conflict
- **close-task.sh 现状**：merge 失败立即 exit 1，不删 task 分支（v1 现有 I-CT3 保护）
- **PM 操作**：手动解 conflict（在 req worktree 里）→ 重跑 close-task

### 7.9 并行场景：N 个待验收一起呈交，主 Claude context 撑大

- 主 Claude reduce 时不要一次 dump 所有 diff 全文
- 默认行为：列摘要（task ID / 文件数 / +/- 行数 / review 结论），PM 选哪个深入再拉 diff
- 软 cap 建议：一次响应最多展开 3 个 task 详情，多则提示 PM 分批

### 7.6 codex 进程崩溃 / 长跑超时

- 新窗口里的 Claude 看 codex Bash exit code 处理（v1 现有 `_gate.sh` 的 I-AD2 后置校验）
- 非 0 退出 → task-execute 调 `task-transition --fail-execution` 回 "待确认"
- 长跑超时：新窗口里 Claude 用 Bash run_in_background + Monitor，Monitor 阻塞主**新窗口** Claude turn 直到 codex 退出（不影响主窗口）。如果 PM 觉得太久 → ESC 中断 + 关窗口 + 走 §7.2 中止流程

---

## 8. 实现顺序

| Phase | 内容 | 验收 |
|---|---|---|
| **A0** | **修 invariant：放宽 I-TT2**（`scripts/task-transition.py` `check_serial_constraint` 删除 / 改成 no-op；`INVARIANTS.md` 更新 I-TT2 描述）| 单元测试：同 req 已有"执行中" task 时，第二个 transition --to 执行中 不再被拒绝；test-task-transition.sh 相关 case 调整 |
| A1 | `skills/task-confirm/SKILL.md` 步骤 5 改输出 + 不转状态 + 多候选检测 | 手工测试：跑 /task-confirm 看到对应启动指令（单候选 vs 多候选）；status 仍 "待确认" |
| A2 | `skills/task-execute/SKILL.md` 入口：无参数找唯一 + 自动 cd + transition | 手工测试：新窗口任意 cwd 跑 `/task-execute`，自动找到 task 并 cd；多候选时报错列出 |
| A3 | `skills/task-status/SKILL.md` 加多 task 摘要 + "待验收" / "待启动" 提示文案 | 手工测试：扫到对应状态有提示，能区分 1 个 vs N 个 |
| A4 | `templates/CLAUDE.md.tmpl` 角色表 + 工作流文案改写 + 并行说明 | 手工 review |
| A5 | 测试套（详 §11） | T1-T7 全绿 |
| A6 | 业务项目升级（admin console4） | 业务项目能成功跑新流程 + 并行场景演练 |

**预计改动**：约 4-5 个文件 / 0 新建脚本 / 0 新建 hook / 1 个 invariant 修改（I-TT2）。

---

## 9. 暂不做

- 多 task 并行（D0 决议；未来要做时回头看 v3 plan）
- Superset MCP 集成（D1 决议）
- 任何 sentinel / hook / wakeup 自动化（D3 决议）
- `task-recover.sh` 等专用脚本（直接调 task-transition --fail-execution 即可）
- 新 Claude pane 心跳 / heartbeat（无独立 Claude 概念）

---

## 10. v3.5 删除/复用矩阵

| v3.5 段落 | 本方案处理 | 原因 |
|---|---|---|
| §4.1 task-confirm 调 3 个 MCP 工具 | ❌ **删除** | 改为 echo 启动指令 |
| §4.2 task-events 接口（FM2 修订） | ❌ **不需要新 append** | 仅 v1 现有 task-transition.py 自己 append；新代码不写事件 |
| §4.3 scan-task-done.sh | ❌ **删除** | 无 reducer |
| §4.4 UserPromptSubmit hook | ❌ **删除** | 无 hook |
| §4.5 ScheduleWakeup adaptive | ❌ **删除** | 无主动唤醒 |
| §4.6 失败/超时（13 行表）| 🟡 **简化**（§7） | 4 个场景，全部走 task-transition |
| §6.2 task-execute 自跑 review 满足 I-TT3 | ❌ **删除** | PM 在新窗口手动走 v1 现有 /task-submit 流程 |
| §7.6 task-recover.sh | ❌ **删除** | 直接调 task-transition --fail-execution |
| §7.7 close-task 清理 superset workspace | ❌ **删除** | 无 superset workspace |
| §11 G1-G15 加固 | 🟡 **大量删除**：保留 G4 / G7 / G12 / G13；删 G5（无 reducer）/ G6（无 PID 追踪）/ G14（无 abort）/ G15（无 wakeup） | 大部分加固为并行/异步设计 |
| §11.5 T1-T11 + T12-T14 测试 | 🟡 **取舍**：保留 T5 / T7（adapter 越界）；删其余 | 大部分测试为 sentinel/wakeup/superset 设计 |
| 决策记录 D1/D2/Q1-Q6 | ❌ **不再适用** | Superset MCP 集成已废 |

---

## 11. 测试清单

| # | 测试 | 反例 |
|---|---|---|
| T1 | task-confirm 输出格式正确（单候选） | 跑 `/task-confirm <task-file>`，输出含 worktree 路径 + `/task-execute`（无参）提示；状态仍 "待确认" |
| T2 | task-confirm 输出格式正确（多候选） | 已有 1 个 "待确认" + worktree 已建 → 再跑 `/task-confirm`，输出强制 `/task-execute <abs-path>`（带显式参数提示） |
| T3 | task-execute 无参数找唯一 | 仅 1 个 "待启动" → `/task-execute` 自动选定 + cd worktree + 转执行中 |
| T4 | task-execute 多候选报错 | 2 个 "待启动" → `/task-execute` 报错列出，不转状态、不 cd |
| T5 | task-execute 入口 transition | 状态 "已完成" → 跑 `/task-execute` → 报错退出，不调 transition |
| T6 | **I-TT2 放宽（D7）**：同 req 多 task 同时执行允许 | 同 req 已有 task-005 "执行中" → 跑 `/task-execute task-006` → 不再 serial 拒绝，task-006 也转 "执行中" |
| T7 | task-confirm 同 branch worktree 冲突拦截 | 已存在 `.worktrees/task-005-foo/` → 跑 `/task-confirm requirements/.../task-005-foo.md` → 步骤 4 前置检查拒绝 |
| T8 | adapter 越界写入检测（v1 现有 I-AD2 沿用） | 跑 task 时 prompt 引导写别 task worktree → adapter 后置校验失败 |
| T9 | 并行场景：3 task 同时执行 + close 顺序 | 启 3 个 "执行中" → 全部转 "待验收" → 一个一个 close-task；后 close 的 merge 走 fast-forward 或 merge commit |

测试用 v1 现有 plain bash + `tests/helpers/`，命名 `tests/v4_T<N>_<slug>.sh`。

---

## 12. 决策溯源

| 时间 | 事件 | 输出 |
|---|---|---|
| 2026-04-22 | task-005 worktree 内混入代码 | v2 worktree 物化方案搁置 + I-CT7/I-CT8 事件流审计加固 |
| 2026-04-24 | admin console4 task-001 codex 孤儿事件 | v3 并行方案出现 |
| 2026-04-24 | autoplan 6 路评审 + plan-eng-review | v3 收敛 |
| 2026-04-25 | PM 决定 v3 暂停 | TODOS 标 paused |
| 2026-04-25 | PM 提"独立 IDE Claude 实例"思路 | v3.5 (Superset MCP) 出现 |
| 2026-04-25 | autoplan eng review (v3.5) | 13 critical/high gap，5 critical 修入主体，8 进 todos |
| 2026-04-25 | PM 反思："是不是开窗口的事情让用户自己来做就好" | **v4 出现，本文档** |
| 2026-04-25 | PM 提议简化新窗口操作（自动找唯一 task + 自动 cd） | D6 加入；新窗口操作缩到 2 步 |
| 2026-04-25 | PM 选 A：v4 改成并行原生（不需要 v3 复杂度） | D0 改并行，D7 放宽 I-TT2，§3 加并行场景流，§7 加并行 fallback，§11 加 T6/T9 |

---

## 13. 风险

### 13.1 PM 体验：多一个手动步骤

- 缓解：启动指令模板化，PM 可一键复制粘贴
- 缓解：IDE 集成可能（VS Code / Cursor 提供 task runner，PM 配置一次后变成 "点按钮启动"）—— 但**不是本方案的责任**，PM 自己配

### 13.2 PM 忘记开新窗口 → task 卡 "待确认"

- 缓解：`/task-status` 主动提示
- 缓解：主 Claude 在 PM 任意输入时检测并提示

### 13.3 PM 跑完不回主窗口 → 主 Claude 不知道完成

- 缓解：状态在 "待验收" 是合法状态，PM 任何后续输入都会被检测
- 缓解：`/task-status` 显示 "待验收 task: N"

### 13.4 IDE 启动 Claude 的方式不一致

- VS Code / Cursor / Trae / Windsurf 启 Claude 的方式不同
- 缓解：启动指令模板提供两种：CLI（`claude`）+ "在你的 IDE 里开新 Claude tab"
- PM 自己根据 IDE 选

### 13.5 仍然存在的 v1 现有 bug（不阻塞本方案）

这些是 v1 现有问题，本方案不引入也不修复。建议另起 issue 跟踪：

- FM6 v1: codex 非 0 退出后 task-execute 是否自动调 `task-transition --fail-execution`？需查 v1 现状
- FM7 v1: `task-transition.py` `update_field` 写状态字段成功但 `append_event` 失败时不回滚（task-transition.py:211 忽略 append 子进程返回码），违反 I-CT7 fail-closed
- FM8 v1: 命名清理（task_short_id / task_stem）

### 13.6 并行特有风险（D0）

- **PM 认知负担**：同时管 5+ 新窗口可能混乱。**自然限制**——PM 自己决定开几个，不像 v3 怕 AI 自作主张
- **merge conflict**：同一文件多 task 改 → 后 close 的 task merge 报 conflict。v1 现有 close-task fail-closed，PM 解决后重跑
- **task 依赖**：PM 自己判断；task-confirm 检测到 "依赖：" 字段非空且依赖未 close → 警告但不阻止
- **review 工具并发跑**：task-005 / task-006 在两个新窗口同时跑 `/qa`（如果 qa 用 browse），可能竞争浏览器实例。**缓解**：PM 操作时序自然错开；如真需要可加锁（暂不做）
- **req 进度感知**：v1 假设"一个时间一个 task"，进度文案"task 1/N 完成"在并行时变成"task X 完成（剩余执行中：Y, 待验收：Z）"——`/task-status` 文案需更新

---

## 附录：文件改动清单

**改**：
- `skills/task-confirm/SKILL.md`（步骤 5 改输出文案 + 不转状态）
- `skills/task-execute/SKILL.md`（入口加 status check + transition）
- `skills/task-status/SKILL.md`（加待验收/待启动提示文案）
- `templates/CLAUDE.md.tmpl`（角色表第 18 行 + 工作流文案）

**新建**：
- 5 条测试 `tests/v4_T*.sh`

**删除**（vs v3.5 plan）：
- 不创建 `scripts/scan-task-done.sh`
- 不创建 `.claude/hooks/task-done-check.sh`
- 不创建 `scripts/task-recover.sh`
- 不改 `templates/settings.json.tmpl`（无新配置）
- 不改 `scripts/close-task.sh` / `cancel-req.sh`（无 superset workspace 清理）

**保留不变**：
- `scripts/` 下全部脚本
- `.claude/hooks/` 不存在或不动
- v1 现有事件流 / I-CT7/I-CT8 审计完全沿用
