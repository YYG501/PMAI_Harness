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

> **2026-04-26 sync 备注**：stage 5/6 重设计已 ship（commits `90997a3`/`a6d33ab`/`dfd5f5f`/`f9d9e3a`），引入 `/task-spec` 作为 stage 6 入口 + `doc-update` 大改 + `task-execute` 末尾"PM 反馈分流" + `close-task` 末尾"auto-chain 提示下一个 task"。本方案在 stage 5/6 ship 之后接入，**不重复这些工作**。完整 stage 6 入口序列见下图。

```
PM ─[/task-spec task-005]──▶ 主 Claude（在 req worktree）
       │ (stage 5/6 新 skill：单 task 详细文档生成器，PM 看后改 task 文件)
       │
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

新窗口 Claude 接续 (2026-04-26 单窗口 lifecycle 修订)：
   /task-submit (在新窗口里跑完整验收流程)
     ├─▶ 文档偏差 + 自审记录 + review_completed 事件
     ├─▶ task-transition.py --to 待验收
     ├─▶ **直接在本窗口拉 diff + review 摘要呈交 PM**（不再"回主窗口"）
     ├─▶ PM 通过 → 本窗口跑 /close-task
     │     └─▶ close-task auto-chain 提示 "task-005 已 close。关掉本窗口，去主窗口启下一个 task"
     └─▶ PM 打回 → 本窗口直接转执行中 + PM 反馈写 task 文件 → 应用 stage 5/6 PM 反馈分流策略 → 继续修

PM 关新窗口（task 已 close 或继续修中）

[主窗口] 几乎不参与单 task lifecycle —— 只在跨 task / 兜底场景出现：
- 兜底 1：PM 忘记某窗口跑完没回 → 任意输入触发 preamble 摘要 → 主 Claude 提示 "task-X 待验收，去对应新窗口验收"
- 兜底 2：PM 关窗口要中止 → 输入 "放弃 task-X" → 主 Claude 调 fail-execution
```

**并行场景流（D0 并行原生）**：

```
主窗口 PM 连续 confirm 多个 task：
  PM: /task-spec task-005 → /task-confirm tasks/task-005-*.md
  PM: /task-spec task-006 → /task-confirm tasks/task-006-*.md
  PM: /task-spec task-007 → /task-confirm tasks/task-007-*.md
  3 个 worktree 已建，3 个 task "待确认"

PM 决定开几个并行窗口：

┌─ 新窗口 A (task-005) ──┐  ┌─ 新窗口 B (task-006) ──┐  ┌─ 新窗口 C (task-007) ──┐
│ claude                 │  │ claude                 │  │ claude                 │
│ /task-execute task-005 │  │ /task-execute task-006 │  │ /task-execute task-007 │
│ → cd / transition 执行中│  │ → cd / transition 执行中│  │ → cd / transition 执行中│
│ → Bash codex + Monitor │  │ → Bash codex + Monitor │  │ → Bash codex + Monitor │
│ → /task-submit 自审 +  │  │ → /task-submit 自审 +  │  │ → /task-submit 自审 +  │
│   review + 转待验收     │  │   review + 转待验收     │  │   review + 转待验收     │
│ → **本窗口呈交 PM 验收**│  │ → **本窗口呈交 PM 验收**│  │ → **本窗口呈交 PM 验收**│
│ → 通过/打回             │  │ → 通过/打回             │  │ → 通过/打回             │
│ → /close-task           │  │ → /close-task           │  │ → /close-task           │
│ → "关窗口去主启下一个"   │  │ → "关窗口去主启下一个"   │  │ → "关窗口去主启下一个"   │
└────────────────────────┘  └────────────────────────┘  └────────────────────────┘
   git worktree 天然隔离，3 个并发 codex 互不干扰
   每个 task 独立完成完整 lifecycle，互不耦合

主窗口期间一直空闲（除非 PM 想批量看总览，可主动跑 /task-status）
```

**关键差异 vs v3 并行**：
- v3：AI 主动 spawn 后台进程 + ScheduleWakeup poll + hook 兜底 + reducer mutex
- v4：**PM 手动开窗口** + **每个 task 在自己窗口里走完整 lifecycle** + 主窗口纯协调
- 并行复杂度归零——多进程协调在 PM 大脑里发生，AI 只负责"窗口 = task"的一致映射

**关键差异 vs v3.5**：
- 不存在 "新 Claude 是项目经理"——它就是 PM 启的普通 Claude，跑 v1+stage5/6 现有 SKILL
- 主 Claude 不主动收口（兜底兜底）
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
  # 已有 N 个待启动 → 新窗口推荐用短 ID（Pass 4 F1 修订：依赖 Pass 2 F2 短 ID 模糊匹配）
  cat <<EOF
✅ Task ${TASK_SHORT_ID} 准备就绪（worktree: .worktrees/${TASK_STEM}）。

⚠️ 当前有 ${PENDING_COUNT} 个待启动 task，新窗口请用短 ID（依赖 task-execute 短 ID 模糊匹配）：

  /task-execute ${TASK_SHORT_ID}

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
- **🆕 依赖前置检查**（2026-04-26 PM 决议主防线）：扫 task 文件「依赖」section 提取 `task-NNN`；扫同 req 下每个依赖 task 状态；任一非"已完成" → **拒绝创建 worktree**，主窗口直接报错：

  ```
  ❌ task-006 依赖 task-005，但 task-005 当前状态是「执行中」。
     请先去 task-005 对应窗口完成验收 + close，然后重跑 /task-confirm。
     （task-005 worktree: .worktrees/task-005-...，PM 可以去那个窗口验收）
  ```

  通过则继续步骤 4 创建 worktree + 步骤 5 输出启动指令

**失败 fallback**：步骤 4 (create-task-worktree.sh) 失败 → 报错给 PM 不输出启动指令；步骤 5 本身只是 echo，不会失败。

**关键**：**步骤 5 不调 task-transition.py**——状态保持 "待确认"，由新窗口的 `/task-execute` 转。这意味着如果 PM 看到指令但没在新窗口跑，task 会一直停在 "待确认"，下次 `/task-status` 会提示。

### 4.2 `skills/task-execute/SKILL.md` 入口加 transition + 无参数模式 + 自动 cd

新窗口 Claude 跑 `/task-execute [<task-file>]`：

```bash
# 步骤 1：定位 task 文件（无参数 → 自动找；短 ID → 模糊匹配；有完整路径 → 直用）
TASK_FILE="${1:-}"

# Pass 2 修订 F2：短 ID 模糊匹配
if [ -n "$TASK_FILE" ] && [[ "$TASK_FILE" =~ ^task-[0-9]{3}$ ]]; then
  REPO_ROOT=$(git rev-parse --show-toplevel)
  MATCHES=$(find "$REPO_ROOT/requirements/active" -name "${TASK_FILE}-*.md")
  COUNT=$(echo "$MATCHES" | grep -c .)
  case "$COUNT" in
    1) TASK_FILE="$MATCHES"; echo "🎯 短 ID 匹配: $TASK_FILE" ;;
    0) echo "❌ 找不到 $TASK_FILE-*.md。建议: /task-status 看可用 task"; exit 1 ;;
    *) echo "⚠️ 短 ID $TASK_FILE 匹配多个，请显式完整路径："
       echo "$MATCHES" | sed 's/^/  \/task-execute /'
       exit 1 ;;
  esac
fi

if [ -z "$TASK_FILE" ]; then
  # D6 无参数模式（Codex C1 修订：active req 通常在 req worktree 不在主仓）
  # 必须扫两个位置：主仓 requirements/active + .worktrees/req-*/requirements/active
  REPO_ROOT=$(git rev-parse --show-toplevel)
  MAIN_REPO_ROOT=$(git -C "$REPO_ROOT" rev-parse --git-common-dir | xargs dirname 2>/dev/null \
                    || echo "$REPO_ROOT")
  cd "$MAIN_REPO_ROOT"

  # 扫两个位置（参考 status-view.py:131 模型）
  ACTIVE_PATHS=("requirements/active")
  for wt in .worktrees/req-*; do
    [ -d "$wt/requirements/active" ] && ACTIVE_PATHS+=("$wt/requirements/active")
  done

  CANDIDATES=$(for p in "${ACTIVE_PATHS[@]}"; do
    find "$p" -name 'task-*.md' -exec grep -l '^\*\*状态：\*\* 待确认$' {} \; 2>/dev/null
  done | while read f; do
    stem=$(basename "$f" .md)
    [ -d "$MAIN_REPO_ROOT/.worktrees/$stem" ] && echo "$f"
  done | sort -u)
  COUNT=$(echo "$CANDIDATES" | grep -c .)

  case "$COUNT" in
    0) echo "❌ 没有待启动的 task。请先在主窗口 /task-confirm <task-file>"; exit 1 ;;
    1) TASK_FILE="$CANDIDATES"
       # Pass 1 修订 #2：诊断行立即打印（在 transition 之前），给 PM progress feedback
       echo "🎯 自动选定: $TASK_FILE"
       echo "    (D6 无参数模式：扫到唯一待启动 task)" ;;
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

# 步骤 2.5：依赖前置 gate（2026-04-26 PM 决议加 — 双层防御兜底层）
# 主防线在 task-confirm 步骤 4 之前（详 §4.1 修订）；本层是 fail-closed 极端兜底
# 防：(a) PM 手动跑 task-transition.py 强改状态绕过 task-confirm
#     (b) 未来调用路径变化（其他入口绕过 task-confirm）
# 读 task 文件「依赖」section，扫所有依赖 task 状态必须全 "已完成"
DEPS=$(awk '/^## 依赖$/,/^## /' "$TASK_FILE" | grep -oE 'task-[0-9]{3}' | sort -u)
if [ -n "$DEPS" ]; then
  for dep_id in $DEPS; do
    # active 找不到就找 closed
    dep_file=$(find "$REPO_ROOT/requirements/active" -name "${dep_id}-*.md" 2>/dev/null | head -1)
    [ -z "$dep_file" ] && \
      dep_file=$(find "$REPO_ROOT/requirements/closed" -name "${dep_id}-*.md" 2>/dev/null | head -1)
    [ -z "$dep_file" ] && {
      echo "❌ 依赖 $dep_id 找不到对应 task 文件，请检查 task 文件「依赖」字段拼写"
      exit 1
    }
    dep_status=$(grep '^\*\*状态：\*\*' "$dep_file" | sed 's/^\*\*状态：\*\* //')
    if [ "$dep_status" != "已完成" ]; then
      echo "❌ $TASK_STEM 依赖 $dep_id，但 $dep_id 当前状态是「$dep_status」"
      echo "   请先去 $dep_id 对应的窗口完成验收 + close，然后重跑本命令"
      echo "   （如想跳过依赖检查强制启动，请改 task 文件「依赖」字段后重跑）"
      exit 1
    fi
  done
  echo "✅ 依赖检查通过：$DEPS 全部已完成"
fi

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
    # Pass 2 修订 F1：错误退出推断意图给 next-step 提示
    echo "❌ task 状态是 '$STATUS'，不能 /task-execute。"
    case "$STATUS" in
      "已完成")  echo "   建议: /close-task $TASK_STEM 或 /task-status 看全局" ;;
      "待验收")  echo "   建议: 回主窗口告诉主 Claude 验收（这个 task 已经跑完了）" ;;
      *)         echo "   建议: /task-status 看当前所有 task 状态" ;;
    esac
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

### 4.4 主窗口收口机制（2026-04-26 单窗口 lifecycle 修订：降级为兜底）

**核心改动**：单窗口 lifecycle 后，主窗口**不再是主收口路径**。验收 + close 都在新窗口完成，主窗口几乎不参与单 task lifecycle。

**主窗口仍然需要的 preamble 行为（兜底场景）**：

兜底场景 1：**PM 忘记某窗口跑完没回**——比如 PM 关了 task-006 的新窗口（误关），task 状态留在 待验收 但 PM 忘了去验收。
兜底场景 2：**PM 想跨 task 看总览**——比如同时跑 5 个，想知道现在状态如何。

**preamble 修订**（仍然落地，作为兜底）：

修改 `scripts/skill-preamble.sh` 末尾段（约 line 220 前后）增加：

```bash
# v4 新增：preamble 输出 task-status 摘要（仅当有 active req 时）
# 单窗口 lifecycle 下作为兜底——主路径在新窗口里完成
if [ -n "$ACTIVE_REQ" ] || ls "$MAIN_REPO_ROOT"/.worktrees/req-* >/dev/null 2>&1; then
  python3 "$MAIN_REPO_ROOT/.claude/scripts/status-view.py" --summary 2>/dev/null || true
  # 输出格式：
  #   📋 task 概览: 执行中 N1 / 待验收 N2 / 待启动 N3
  #   （N2 > 0 时附加："⚠️ N2 个 task 待验收，请去对应新窗口验收（或 /task-status 看详情）"）
fi
```

**仍需要修 `scripts/skill-preamble.sh:78` `_find_active_req_in`**（Codex C3）：扩展扫 `.worktrees/req-*`，否则主窗口的 ACTIVE_REQ/ACTIVE_TASK 仍空。

**仍需要给 `scripts/status-view.py` 加 `--summary` 模式**。

**主路径不再是 "PM 任一输入 → 主 Claude 拉 diff 呈交"**。改为：
- 验收/打回/close 全部在新窗口完成（详 §6 task-submit / close-task 修订）
- 主窗口 preamble 提示 = 兜底，告诉 PM 还有遗漏的 task 要回新窗口处理

**主动总览**：PM 想看跨 task 总览（比如管理 N 个并行）→ 在主窗口跑 `/task-status` 拿全列表。

### 4.5 中止 task（Codex C7 修订：意图识别落 CLAUDE.md.tmpl 而非 preamble）

PM 想中止 → 关新窗口（无副作用，state 仍在 "执行中"）→ 回主窗口用**任何自然语句**表达放弃意图。

**实现位置（C7 修订）**：原 plan 写"主 Claude preamble 意图识别"——错。shell preamble 拿不到用户原话。正确位置：

- **CLAUDE.md.tmpl 行为规则段**：明确"PM 输入含关键词 + 有 task ID 上下文 → 主 Claude 主动调 task-transition --fail-execution"
- 这是**主 Claude 自身的对话行为约定**，不是脚本能做的

**关键词触发规则**（写进 CLAUDE.md.tmpl）：扫 PM 输入含 `放弃 / 取消 / abort / cancel`，且能从上下文推断 task（最近一次 /task-confirm 提到的 task ID，或 active "执行中" task 唯一时直接绑定）→ 触发中止。

示例 PM 输入（全部识别）：
- "放弃 task-005"
- "取消 005"
- "abort 这个"（在 task-005 是唯一 "执行中" 时）
- "我把新窗口关了，不要那个 task 了"
- "cancel task-005-superset"

主 Claude 识别后调：

```bash
python3 .claude/scripts/task-transition.py "$TASK_FILE" --fail-execution --reason "aborted_by_pm"
```

task 回到 "待确认"，worktree 保留供 PM 检查 dirty diff。**不需要 task-recover.sh / PGID 树杀**——新窗口里的 codex 进程会被 PM 关窗口 + OS 信号自然清理。

**歧义处理**：如果 PM 输入只有"放弃"无 task ID 且当前有多个 "执行中" task，主 Claude 列出后问 PM 哪个；如果只有 1 个 "执行中"，直接对它操作（默认）。

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

## 6. 各 skill 改动总览（2026-04-26 已 align stage 5/6 ship 后现状）

| Skill | 改动 | stage 5/6 drift 备注 |
|---|---|---|
| `skills/task-spec/SKILL.md` | **改**（2026-04-26 PM 决议加依赖结构化）| 🆕 stage 5/6 新增 skill；v4 入口在它之后接管。**v4 增量改动**：写 task 文件时「依赖」字段填**结构化** task ID 列表（而非"无"或文字描述），格式 `- task-NNN (一句话说明为什么依赖)`。无依赖时仍写"无" |
| `skills/task-plan/SKILL.md` | **改**（2026-04-26 PM 决议加并行规划）| stage 5/6 大改 (+183 行)，已半文字讨论顺序/并行。**v4 增量改动**：要求 `task-plan.md` 必须包含一节"## 执行顺序与并行性"，输出 ASCII 依赖图 + 并行 lanes 分组 + PM 启动建议（哪些可同时启） |
| `templates/task.md.tmpl` | **微改**（依赖字段格式说明）| 现状 `## 依赖\n无`。v4 改：在「依赖」字段上方加注释说明结构化格式（`- task-NNN (说明)`），让 task-spec 写时有 reference |
| `skills/task-confirm/SKILL.md` | **改**：步骤 5 删 spawn subagent，改输出启动指令；步骤 5 不调 task-transition | 仓库现状未变（0 commits since v4 plan 创建）|
| `skills/task-execute/SKILL.md` | **改**：入口加 status check + transition --to 执行中 + 自动 cd worktree + **步骤 2.5 依赖前置 gate**（详 §4.2 修订） | stage 5/6 已加末尾"PM 反馈分流策略"段；v4 改的是入口 step 1-3 + 新加 2.5 依赖检查；**与分流段不冲突** |
| `skills/task-submit/SKILL.md` | **改**（2026-04-26 单窗口 lifecycle 修订）| stage 5/6 现有 SKILL：转 待验收 后提示 "回主窗口告诉主 Claude"。**v4 改为：在本窗口（task worktree）直接拉 diff + review 摘要呈交 PM 验收**。PM 通过 → 本窗口跑 /close-task；PM 打回 → 本窗口直接转 执行中 + PM 反馈写 task 文件 → 应用 stage 5/6 PM 反馈分流策略继续修。**不再"回主窗口"**——主窗口降级为兜底（详 §4.4） |
| `skills/task-status/SKILL.md` | **微改**：(a) 加 `--summary` 模式（一行结论 `📋 task 概览: 执行中 N1 / 待验收 N2 / 待启动 N3`，给 §4.4 preamble 调用）；(b) 完整模式（无参数）扫到 "待确认" + worktree 已建 → 提示 "等待 PM 在新窗口启动"；扫到 "待验收" → 提示 "请去对应新窗口验收（task 在该 worktree 里跑过完整 review）" | 仓库现状未变 |
| `skills/close-task/SKILL.md` | **改**（2026-04-26 单窗口 lifecycle 修订 + Codex C9）| stage 5/6 已加 `--skip-doc-update` + 末尾 auto-chain "下一个 task 是 task-NNN，继续吗？(Y/n)"。**v4 修改要点**：(a) close-task 在新窗口里跑（cwd 是 task worktree，脚本自己处理 cd 到 main repo 跑 merge）；(b) **末尾 auto-chain 文案改为明确指引**："✅ task-005 已 close。**关掉本窗口**（task 已结束）→ 去主窗口启下一个 task：建议下一个是 task-006（[title]），可以跑 /task-spec task-006 → /task-confirm tasks/task-006-*.md"。**不再问"继续吗"**（暗示在本窗口继续，但其实做不到——本窗口已经是 task-005 worktree） |
| `skills/doc-update/SKILL.md` | **不动** | 🆕 stage 5/6 大改 (+163 行)，被 close-task 内部调用；v4 不接触 |
| `skills/cancel-req` | **不改** | 仓库现状未变 |
| `templates/CLAUDE.md.tmpl` 角色表 | **改第 18 行**：`Suborchestrator | 单 task owner ...` → `新窗口 Claude | PM 在新窗口启动的 Claude 实例，跑单 task；位置在 task worktree 里` | 仓库现状未变 |
| `templates/CLAUDE.md.tmpl` 工作流文案 | **改**：解释"PM 手动开新窗口"模式，加"中止流程"，加 `/task-spec → /task-confirm → ...` 完整 stage 6 入口序列说明 | stage 5/6 入口序列要写明 |

**不动**：
- `scripts/exec-adapters/`（v1 现有 codex.sh / cursor-agent.sh / manual.sh / _gate.sh 全部保留）
- `scripts/create-task-worktree.sh` / `task-transition.py` / `check-branch.sh`（v1 现状全保留——D7 修 task-transition.py 是单独 invariant 改动，不算 skill 改动）
- `.claude/hooks/`（不引入新 hook）

**stage 5/6 ship 后实际改动估算（2026-04-26 多次修订汇总）**：
- v4 plan **直接改的 skill**：6 个（task-confirm 重写步骤 5 / task-execute 入口加 transition + cd + 扫双位置 + **依赖前置 gate** / task-status 加 --summary 模式 + 多 task 摘要 / task-submit **改新窗口直接呈交验收** / **close-task 改新窗口跑 + auto-chain 文案** / **task-plan 加并行规划** / **task-spec 加依赖结构化**）
- v4 plan **不动的 skill**：1 个（doc-update —— stage 5/6 已 ship，v4 不动）
- v4 plan **改动的 scripts**：3 个
  - `task-transition.py`（D7 删 check_serial_constraint + 顺手修 FM7 事务性）
  - **`skill-preamble.sh`**（C2/C3 修订：扩展 `_find_active_req_in` 扫 .worktrees/req-* + 末尾加 status-view --summary 调用）
  - **`status-view.py`**（C2 修订：加 `--summary` 模式输出一行结论）
- v4 plan **invariant 改动**：1 个（INVARIANTS.md I-TT2 + I-CT7 文档化 FM7 fix）
- 模板改动：2 个（CLAUDE.md.tmpl 角色表 + 工作流文案 + 中止意图识别规则 + task 文件真相源规则；task.md.tmpl 依赖字段格式说明）
- 测试新增：~11 条（T11-T15 + Codex C10 6 条新断言 + T22 单窗口 lifecycle + T23 依赖 gate）

**总改动面**：**11 个文件改动 + ~11 测试**（vs 原估算 4-5 文件 + 5-7 测试）。增量来自三处：(1) Codex outside voice 发现的 plan 隐含假设需新代码支持；(2) PM 单窗口 lifecycle 决议（task-submit/close-task 改流程）；(3) PM 依赖结构化决议（task-plan/task-spec/task-execute 依赖 gate）。

---

## 7. 失败 fallback

### 7.1 PM 看到启动指令但没在新窗口跑

- task 状态停在 "待确认"，worktree 已建但空
- 下次 PM 在主窗口任意输入，preamble 扫到 → 主 Claude 提示 "task-X 已 confirm 但未启动，需要继续吗？"
- PM 选继续 → 主 Claude 重复输出启动指令；PM 选放弃 → 主 Claude 删 worktree + 状态保持 "待确认"（或 PM 决定 cancel）

### 7.2 PM 在新窗口跑了但中途关窗口（Codex C8 修订：D7 后无 serial 阻塞）

- task 状态停在 "执行中"。**D7 放宽 I-TT2 后不阻塞 sibling**，但会污染 status / 验收队列
- PM 回主窗口说 "放弃 task-X" → 主 Claude 调 `task-transition --fail-execution --reason aborted_by_pm` → 回 "待确认"
- worktree 保留供 PM 检查 dirty diff（参考 v3.5 §7.6 task-recover 思路，但**不需要新脚本**——直接调 task-transition）
- 故障可见性：abandoned `执行中` task 会被 §4.4 主窗口 preamble 摘要持续提示，PM 不会忘掉它

### 7.3 PM 跑完没回主窗口

- task 状态在 "待验收"，无负面影响
- 下次 PM 任意输入触发 SKILL → preamble §4.4 修订摘要扫到待验收 → 主 Claude 提示验收
- 完全等价于 v1 现状下 PM 走完 /task-submit 不及时回主窗口的场景

### 7.10 PM 打回后继续修（2026-04-26 单窗口 lifecycle 修订）

**单窗口 lifecycle 下大幅简化**——验收 + 打回都在新窗口完成，**没有跨窗口分裂**。

- PM 在新窗口里看 task-submit 呈交的 diff + review 摘要 → 选"打回"
- 新窗口 Claude 直接：
  1. `task-transition.py --to 执行中 --note "PM 反馈：..."`（写进 task 文件 PM 反馈 section）
  2. 应用 stage 5/6 的"PM 反馈分流策略"——一行识别"行为修订 vs Bug 修复"
  3. PM 确认分类（任意输入 / wrong）
  4. 直接继续修，无需切窗口、无需重新启动

**不需要兜底**：因为 task-submit 呈交、PM 选打回、继续修全在同一个新窗口里发生，PM 不可能"忘记"或"找不到入口"。

**唯一例外**：如果 PM 误关了新窗口才发现要打回（场景罕见）→ 重开 `/task-execute task-XXX`（状态已是"执行中"，入口不 transition，直接进 stage 5/6 PM 反馈分流）。这是 §7.4 / §7.11 兜底路径的延伸，不是主路径。

### 7.11 task 文件真相源 + close-task dirty req wt（Codex C4/C5 修订）

**问题**：task 文件存在两处副本——req worktree 里的（`requirements/active/<req>/tasks/task-NNN.md`）和 task worktree 里的（task worktree 是从 req 分支切出来的，自然包含同一个 task 文件）。`/task-execute` 改状态字段（"待确认"→"执行中"）时改哪份？

**v4 决议**：
- **task 状态字段写入**：必须在 **task worktree** 里改（因为 task-execute SKILL 步骤 2 已经 `cd $WORKTREE_ABS`），改后 commit 到 task 分支
- **req worktree 里的 task 文件副本**：不动；它会在 close-task merge 时通过 git merge 自然 sync（task 分支的 task 文件改动 merge 进 req 分支）
- **check-branch.sh:337 跨 worktree find 行为**：保留（v1 现状）；状态分裂只在"transition 中途崩"场景出现，I-CT7 事件流审计兜底

**close-task dirty req wt（Codex C5）**：close-task.sh:124 检查 req worktree clean。若 PM 在 req worktree 里手动改了 task 文件（不该这么做但可能发生）→ close-task 拒绝。
- v4 决议：保留 v1 拒绝行为（fail-closed 正确）；CLAUDE.md.tmpl 加规则"task worktree 启动后不要在 req worktree 编辑同 task 的 task 文件"

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
| **A0** | **修 invariant + 顺手修 FM7** —— (1) `scripts/task-transition.py` 删除 `check_serial_constraint` (line 141-156) 或改 no-op；(2) `INVARIANTS.md` 更新 I-TT2 描述；(3) 改写 `tests/test-task-transition.sh:112-138` 两个 case 反向；(4) 顺手修 FM7 transition 事务性 + T15 反例 | 测试全绿 |
| **A1** | **新增 preamble 行为支持主窗口收口**（Codex C2/C3）—— (1) `scripts/skill-preamble.sh:78` `_find_active_req_in` 扩展扫 `.worktrees/req-*`；(2) `scripts/skill-preamble.sh` 末尾加 status-view --summary 调用；(3) `scripts/status-view.py` 加 `--summary` 模式 | T16/T19 通过 |
| **A2** | **改 6 个 skill** —— task-confirm 步骤 5 重写 / task-execute 入口加 transition + cd + 扫双位置 + 短 ID 模糊匹配 + next-step + **依赖前置 gate** / task-status 加 --summary + 多 task 摘要 / **task-submit 改本窗口呈交验收** / **close-task 改本窗口跑 + auto-chain 文案** / **task-plan 加并行规划输出** / **task-spec 加依赖结构化** | T1-T5 + T13-T14 + T22 + T23 通过 |
| **A3** | 模板改写 —— `templates/CLAUDE.md.tmpl`（角色表 + 工作流文案 + 中止意图识别规则 + task 文件真相源规则）；`templates/task.md.tmpl`（依赖字段格式说明） | 手工 review |
| **A4** | 新增 `tests/v4_T*.sh` 单元 + `tests/e2e/v4_*.sh` 端到端 ~11 条 | T13/T14/T16/T22/T23 全部通过 (159 全套 passed)；其他 T 项是 SKILL 行为难自动测，留 manual QA |
| **A5** | 业务项目升级（admin console4） | 业务项目跑新流程 |

**预计改动**（2026-04-26 Codex outside voice 后修订）：8 个文件改动（4 skill + 3 scripts + 1 模板）+ 1 invariant 文档化 + ~10 测试新增。

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
| T10 | close-task auto-chain 在并行场景的文案适应性 | 多个 待启动 task → close-task 末尾 auto-chain 文案是否清晰（不强制让 PM 串行，至少不暗示串行）。预期：发现需要 stage 5/6 改文案，登记 TODO |
| **T11 中止意图识别（§4.5）**| PM 在主窗口任意输入触发 fail-execution | 输入 `放弃 task-005` / `取消 005` / `abort 这个`（task-005 唯一执行中时）→ 主 Claude 都识别并调 fail-execution；输入 `放弃` 无 task ID 且多 task 时 → 主 Claude 列出让 PM 选 |
| **T12 兜底 reduce 触发（§4.4 兜底）**| 主 Claude preamble 摘要在 PM 误关新窗口场景生效 | task 状态 "待验收" + PM 关了新窗口 + 主窗口任意输入 → preamble 输出"📋 待验收 1 ⚠️ 请去对应新窗口"。**注：单窗口 lifecycle 后这是兜底场景测试，不是主路径** |
| **T22 单窗口完整 lifecycle**（2026-04-26 修订）| 新窗口里完成 confirm 后所有步骤 | 新窗口 `/task-execute` → codex 跑完 → /task-submit 自审 → review → 转待验收 → **本窗口呈交 PM diff + review 摘要** → PM 通过 → /close-task → auto-chain 输出"关本窗口去主启下一个 task"。全程不切主窗口 |
| **T23 依赖前置 gate（双层）**（2026-04-26 PM 决议）| 验证两个层都拦：(a) **主防线**: task-confirm 在依赖未满足时拒绝创建 worktree（task-006 依赖 task-005 != 已完成 → /task-confirm task-006 exit 1 + 不建 worktree）；(b) **兜底层**: task-execute 入口绕过 task-confirm 直接调时也拦（手工 task-transition 强改 task-005 状态 → /task-execute task-006 步骤 2.5 exit 1）| 两层都通过+无依赖时通过+任一层拦截时给明确指引 |
| **T13 多 task 摘要格式（§6 task-status）**| task-status 输出多 task 一行结论 | 3 执行中 + 2 待验收 → 输出 `📋 task 概览: 执行中 3 / 待验收 2` 第一行；详情按需展开 |
| **T14 短 ID 模糊匹配（Pass 2 F2）**| `/task-execute task-005` 自动找唯一 task-005-*.md | 1 匹配 → 用 ✓；0 匹配 → 报错；多匹配 → 列出报错 |
| **T15 FM7 transition 事务性回归**| append_event 失败时 task 文件状态字段必须回滚 | 模拟 `.runs/events/` 不可写 → `task-transition --to 执行中` 必须 exit 1 + 状态字段保持原值（不能写成功又静默丢事件） |
| **T16 主仓无参数 /task-execute 能发现 req worktree task**（Codex C1）| `/task-execute` 在主仓 cwd 跑 → 扫到 `.worktrees/req-*/requirements/active/...` 下 task | active req 在 req worktree 时，无参数模式 happy path 可走 |
| **T17 task copy / req copy 状态一致**（Codex C4）| transition 后 task worktree 与 req worktree 里的 task 文件状态字段一致 | 防止状态分裂导致 I-CB10 误判 |
| **T18 I-CB10 在 v4 transition 后允许写**（Codex C10）| task-execute 转 "执行中" 后，新窗口 Claude 可写 task worktree | check-branch.sh 状态字段读取与 task-transition 写入时序正确 |
| **T19 主窗口 task-status 多待验收不 dump 全 diff**（Codex C10）| 5 个待验收 task → /task-status 输出 `📋 概览` 一行 + 5 个 task 摘要，**不**自动拉全 diff | context 不撑爆；PM 显式问哪个再深入 |
| **T20 PM 打回后 /task-execute 可重入**（Codex C6）| 打回后 task 状态 "执行中" + PM 反馈 section 有内容 → /task-execute 不阻塞，进入 stage 5/6 PM 反馈分流流程 | §7.10 路径可走 |
| **T21 close-task 不因 req worktree dirty 卡死**（Codex C5）| 跑完 task → close-task 时 req worktree 应 clean（v4 不在 req worktree 写 task 状态）| §7.11 决议落实 |

测试用 v1 现有 plain bash + `tests/helpers/`：简单单元测试放 `tests/v4_T<N>_<slug>.sh`，复杂端到端放 `tests/e2e/v4_<slug>.sh`（align stage 5/6 已建的 `tests/e2e/` 目录约定）。

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
| 2026-04-26 | PM 触发 /plan-eng-review，发现 stage 5/6 ship 已 drift v4 假设的"v1 现状" | sync v4 plan §3 入口加 `/task-spec`；§6 改动表加 stage 5/6 备注（task-execute 末尾分流段共存、close-task auto-chain 并行 caveat、新 skill task-spec/doc-update 标"不动但要协同"）；§11 加 T10 + 测试目录约定 align tests/e2e/ |
| 2026-04-26 | /plan-eng-review Section 1+3+Codex outside voice 完整跑完 | Section 1: D7 加测试改写 + 顺手修 FM7 + 11/13 v3.5 gap 消失结论。Section 3: 加 T11-T15。**Codex outside voice 找 5 critical + 4 high**：(C1) D6 扫错地方，(C2/C3) "preamble 顺手扫" 是假的，(C5) close-task req wt dirty 风险，(C6) PM 打回路径断，(C7) 中止意图识别落 CLAUDE.md.tmpl 而非 preamble，(C8) §7.2 串行心智残留，(C9) close-task auto-chain 升级阻塞，(C10) 测试缺 6 断言。**改动估算从 4-5 文件升到 8 个文件**——主要新增 skill-preamble.sh + status-view.py 修订支持"主窗口自动收口" |
| 2026-04-26 | PM 提议改为单窗口完整 lifecycle（验收 + 打回 + close 都在新窗口里）| **重大流程简化**：(a) §3 架构图重画——新窗口跑完整 lifecycle；(b) §4.4 主窗口收口降级为兜底；(c) §6 task-submit 改为新窗口直接呈交 PM 验收；(d) §6 close-task auto-chain 文案改"关本窗口去主启下一个"（不再问"继续吗"）；(e) §7.10 PM 打回路径大幅简化——同窗口继续修，删除"新窗口已关 vs 还在"分裂；(f) §11 加 T22 单窗口完整 lifecycle 测试。trade-off：失去主窗口"批量验收"模式，PM 主动跑 /task-status 拉总览补偿 |
| 2026-04-26 | PM 提议加依赖结构化（task-plan 拆分阶段考虑并行 + task-execute 入口检查依赖） | **§7.7 把"依赖 PM 自己判断"升级为"系统帮记录 + 校验"**：(a) §6 task-plan SKILL 加"## 执行顺序与并行性"输出（ASCII 依赖图 + 并行 lanes + 启动建议）；(b) §6 task-spec SKILL 写 task 文件时「依赖」字段填结构化 task ID 列表；(c) §4.2 task-execute 入口加步骤 2.5 依赖前置 gate（依赖未"已完成"则拒绝 + 明确指引）；(d) §6 task.md.tmpl 「依赖」字段加格式说明；(e) §11 加 T23 依赖 gate 测试。改动估算 8 → 11 文件 |
| 2026-04-26 | PM 修正：依赖检查应在主 Agent 创建 worktree 时（task-confirm）做，task-execute 兜底 | **双层防御**：(a) **主防线** §4.1 task-confirm 步骤 4 创建 worktree 之前加依赖检查（fail-fast，主窗口直接报错，不浪费建 worktree）；(b) **兜底层** §4.2 步骤 2.5 保留（防 PM 手动 task-transition 强改状态 / 未来调用路径变化）。T23 升级为双层验证 |

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

### 13.5 v3.5 13 critical/high gap 在 v4 里的命运（2026-04-26 eng review 复核）

**11/13 gap 在 v4 设计层面消失**（因 v4 删 Superset MCP / 无 reducer / 无 sentinel / PM 自启窗口）：FM1（启动序列）/ FM2（events 接口）/ FM3（reducer mutex）/ FM4（crashed 误判）/ FM5（PM 关 pane 卡死）/ FM6（execution_failed 流程）/ FM8（命名）/ FM9（path adapter）/ FM10（close-task superset 清理）/ FM11（prompt 注入）/ FM12（MCP inheritance）/ FM13（自跑 review I-TT3）

**1 个 v1 现有 bug，本轮顺手一并修**（2026-04-26 eng review 决议）：
- **FM7 v1 transition 非事务性**: `task-transition.py:211` `append_event` 子进程返回码被忽略——状态字段写成功但事件追加失败时不回滚，违反 I-CT7 fail-closed。
- **修订位置**：§8 A0 phase 步骤 (4) — 借 D7 改 task-transition.py 时一并修；T15 反例测试覆盖。

**0 个 v4 新引入的 critical gap** —— 主要因为 v4 把"AI 自动协调"的复杂度还给 PM 大脑，gap 来源被砍。

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

---

## /plan-devex-review 报告（2026-04-25）

**Mode**：DX POLISH，**incremental scope**（PM 决议）—— 只跑适用 pass，跳 Pass 5/6/7/8（不适用 PM 单人 workflow 场景）。
**Persona**：PM 自己（admin console4 项目主用户，已熟 v1）。
**Magical moment**：A 候选——`/task-execute` 无参数自动找 + 自动 cd worktree。

### DX 评分

| Dimension | 初评 | 修订后 |
|---|---|---|
| Pass 1 Getting Started | 6/10 | **7/10**（修订 #2 诊断行；拒绝 #1/#3）|
| Pass 2 API/CLI Design | 7/10 | **9/10**（F1 next-step + F2 短 ID 模糊匹配）|
| Pass 3 Error Messages | skipped | — |
| Pass 4 Documentation | 5/10 | **9/10**（F1 短 ID 文案 + F2 意图识别 + F3 status 摘要格式）|
| Pass 5 Upgrade | skipped | — |
| Pass 6 Dev Env | skipped | — |
| Pass 7 Community | n/a | — |
| Pass 8 DX Measurement | n/a | — |
| **Overall** | **6/10** | **8.3/10**（适用 pass 平均）|

**TTHW**：~30s PM 操作（不含 codex 跑）→ 修订后 ~20s（短 ID + 诊断行降低不确定）。Champion tier ✓。

### 落地修订汇总

| Pass | Finding | 落地位置 |
|---|---|---|
| 1 #2 | task-execute 第一秒打印诊断行 | §4.2 case 1) |
| 2 F1 | 错误退出推断意图给 next-step | §4.2 case "*" |
| 2 F2 | 短 ID 模糊匹配 (`/task-execute task-005`) | §4.2 步骤 1 新分支 |
| 4 F1 | 多候选输出改用短 ID 格式 | §4.1 else 分支 |
| 4 F2 | 中止意图识别（PM 不背模板）| §4.5 改写 |
| 4 F3 | task-status 多 task 摘要格式样例 | §6 task-status 行 |

**拒绝**：Pass 1 #1（IDE-specific 启动文案）、Pass 1 #3（macOS pbcopy 自动复制）—— PM 决议保持 plan 简洁。

### GSTACK REVIEW REPORT (2026-04-26 更新)

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 | skipped | (PM 决议) |
| Codex Review | `/codex review` (eng outside voice) | Independent 2nd opinion | 1 (本轮 eng review Section 4) | issues_found | 10 finding (5 critical + 4 high + 1 medium) — Codex 直接读源码发现 plan 假设和实际代码 drift |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 1 (本轮) | issues_resolved | Section 1: D7 测试改写 + FM7 顺手修 + 11/13 v3.5 gap 消失. Section 3: 加 T11-T15. Codex outside voice: 加 T16-T21 + 8 处 plan 主体修订 |
| Design Review | `/plan-design-review` | UI/UX gaps | 0 | skipped | no UI scope |
| DX Review | `/plan-devex-review` | DevEx gaps | 1 (2026-04-25) | issues_resolved | 7 finding，6 落地 plan + 2 拒绝 |

- **CODEX:** Codex 找 10 finding，全部 PM 决议接纳 → plan 主体修订（§4.1 D6 扫双位置 / §4.4 preamble 新增 status-view 调用 / §4.5 中止意图识别落 CLAUDE.md.tmpl / §6 close-task auto-chain 升级阻塞 / §7.2 D7 心智一致性 / §7.10 PM 打回路径 / §7.11 task 文件真相源 + close-task dirty req wt / §11 加 T16-T21 6 个新断言）
- **CROSS-MODEL:** Section 1+3 (Claude) 漏掉 Codex 找的 5 critical + 4 high。这次 cross-model 增量价值极高——证明 plan-only review 不读源码会漏掉关键假设错误
- **UNRESOLVED:** 0（PM 已对所有 finding 决议）
- **VERDICT:** **CLEARED with revisions** —— DX (8.3/10) + Eng (issues resolved) 都已过；plan 主体已修 8 处接纳 Codex critical/high。**改动估算从 4-5 文件升到 8 个文件**（新增 skill-preamble.sh / status-view.py 修订支持主窗口自动收口），Phase A 实施前需充分理解新增 scope
