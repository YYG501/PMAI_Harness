# shellcheck shell=bash
# Fixture helpers: build minimal fake project for testing close/cancel/transition logic
#
# Sets up:
#   $FIXTURE_DIR          - temp dir with initialized project
#   $FIXTURE_DIR/.claude/scripts/  - symlinked to real scripts/ for testing
#   $FIXTURE_DIR/requirements/active/req-001-test/
#   $FIXTURE_DIR/requirements/active/req-001-test/tasks/
#   Real git init, real branches, real worktrees
#
# Usage:
#   fixture_setup
#   # ... run tests ...
#   fixture_teardown

FRAMEWORK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fixture_setup() {
  # Create temp dir
  FIXTURE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pmaitest.XXXXXX")
  export FIXTURE_DIR

  # Create project structure
  mkdir -p "$FIXTURE_DIR/.claude"
  mkdir -p "$FIXTURE_DIR/docs/modules"
  mkdir -p "$FIXTURE_DIR/requirements/active"
  mkdir -p "$FIXTURE_DIR/requirements/closed"
  mkdir -p "$FIXTURE_DIR/prototypes"
  mkdir -p "$FIXTURE_DIR/.runs/events"
  mkdir -p "$FIXTURE_DIR/.worktrees"

  # Symlink real scripts
  ln -s "$FRAMEWORK_ROOT/scripts" "$FIXTURE_DIR/.claude/scripts"

  # Minimal docs skeleton
  touch "$FIXTURE_DIR/docs/PROJECT.md"
  touch "$FIXTURE_DIR/docs/DESIGN.md"
  echo "# Fixture Project" > "$FIXTURE_DIR/CLAUDE.md"
  echo ".runs/" > "$FIXTURE_DIR/.gitignore"
  echo ".worktrees/" >> "$FIXTURE_DIR/.gitignore"

  # Git init on main
  (
    cd "$FIXTURE_DIR"
    git init -b main -q
    git config user.email "test@test.local"
    git config user.name "Test"
    git add -A
    git commit -q -m "init fixture"
  )
}

fixture_teardown() {
  if [ -n "$FIXTURE_DIR" ] && [ -d "$FIXTURE_DIR" ]; then
    # Remove any worktrees first (git prune would complain otherwise)
    if [ -d "$FIXTURE_DIR/.worktrees" ]; then
      for wt in "$FIXTURE_DIR/.worktrees"/*/; do
        [ -d "$wt" ] || continue
        git -C "$FIXTURE_DIR" worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
      done
    fi
    rm -rf "$FIXTURE_DIR"
  fi
  unset FIXTURE_DIR
}

# Create a fake active req with meta at given stage
# Usage: fixture_create_req <req-id> <name> <stage>
fixture_create_req() {
  local req_id="$1"
  local name="$2"
  local stage="${3:-1}"
  local req_branch="$req_id-$name"

  # Create req worktree on new branch (from main)
  (
    cd "$FIXTURE_DIR"
    git worktree add -q -b "$req_branch" ".worktrees/$req_branch" main
  )

  # Create req dir inside the worktree
  local req_dir="$FIXTURE_DIR/.worktrees/$req_branch/requirements/active/$req_branch"
  mkdir -p "$req_dir/tasks"

  # Create meta
  cat >"$req_dir/.req-meta.json" <<EOF
{
  "id": "$req_id",
  "name": "$name",
  "branch": "$req_branch",
  "worktree": ".worktrees/$req_branch",
  "stage": $stage,
  "stage_history": [{"stage": 1, "entered_at": "2026-04-12T10:00:00+08:00"}],
  "status": "active"
}
EOF

  # Create minimal brief.md
  echo "# Brief" > "$req_dir/brief.md"

  # Commit on req branch
  (
    cd "$FIXTURE_DIR/.worktrees/$req_branch"
    git add -A
    git commit -q -m "create $req_id"
  )

  echo "$req_dir"
}

# Create a fake task in a req's tasks/ dir AND commit it to the req branch.
#
# 双轨：
#   fixture_create_task    = v1 单文件（旧格式，inline `**字段：**`）
#   fixture_create_task_v2 = v2 双文件（PM 视图表格 + .engineering.md 工程合同）
#
# 默认 fixture_create_task = v1（保持现有 15 个 suite 不回归）。
# 新写测试用 v2，验证 parser 在生产真实格式上的行为。
# v1/v2 双轨保留至双模式上线后统一清理（见 TODOS.md / docs/归档/完成/设计-新两文件格式对齐.md Q3）。

# v1 单文件 fixture（旧格式）
# Usage: fixture_create_task <req-dir> <task-num> <name> <status> [review_tools]
fixture_create_task() {
  local req_dir="$1"
  local task_num="$2"
  local name="$3"
  local status="${4:-待执行}"
  local review_tools="${5:-/qa}"
  local task_slug="task-${task_num}-${name}"
  local task_file="$req_dir/tasks/${task_slug}.md"

  # req_dir 在某个 req worktree 里。找到 worktree 根
  local req_worktree_root="$req_dir"
  while [ "$req_worktree_root" != "/" ] && [ ! -d "$req_worktree_root/.git" ] && [ ! -f "$req_worktree_root/.git" ]; do
    req_worktree_root=$(dirname "$req_worktree_root")
  done

  cat >"$task_file" <<EOF
# Task $task_num: $name

**状态：** $status
**审查工具：** $review_tools
**分支：** $task_slug
**worktree：**
**开发服务器：**
**创建时间：** 2026-04-12

## 启动前必读
1. docs/modules/test.md

## 任务描述
Test task

## 执行范围
- 新建：test.txt

## 验收标准
- [ ] 完成

## 依赖
无

---

## 执行日志

---

## 文档偏差
无偏差

---

## 自审记录
### 自审 1 - 2026-04-12 10:00
**工具：** /qa
**结果：** pass
**详细发现：** 无
**遗留问题：** 无

---

## PM 反馈
无
EOF

  # Commit task file to req branch so it appears in task worktrees later
  if [ -n "$req_worktree_root" ] && [ -d "$req_worktree_root/.git" ] || [ -f "$req_worktree_root/.git" ]; then
    (
      cd "$req_worktree_root"
      git add -A 2>/dev/null
      git commit -q -m "create $task_slug" 2>/dev/null || true
    )
  fi

  echo "$task_file"
}

# v2 双文件 fixture（PM 视图表格 + .engineering.md 工程合同）
# Usage: fixture_create_task_v2 <req-dir> <task-num> <name> <status> [review_tools] [module]
fixture_create_task_v2() {
  local req_dir="$1"
  local task_num="$2"
  local name="$3"
  local status="${4:-待执行}"
  local review_tools="${5:-/qa}"
  local module="${6:-基础设施}"
  local task_slug="task-${task_num}-${name}"
  local task_file="$req_dir/tasks/${task_slug}.md"
  local eng_file="$req_dir/tasks/${task_slug}.engineering.md"

  # req_dir 在某个 req worktree 里。找到 worktree 根
  local req_worktree_root="$req_dir"
  while [ "$req_worktree_root" != "/" ] && [ ! -d "$req_worktree_root/.git" ] && [ ! -f "$req_worktree_root/.git" ]; do
    req_worktree_root=$(dirname "$req_worktree_root")
  done

  # PM 视图（表格元字段；section 用 --- 分隔）
  cat >"$task_file" <<EOF
# Task $task_num: $name

> 本文件是 PM 视图。工程实现细节见 [\`${task_slug}.engineering.md\`](./${task_slug}.engineering.md)。

---

## 📌 任务卡

| | |
|---|---|
| **状态** | $status |
| **所属模块** | $module |
| **所属模块章节** |  |
| **dev server** |  |
| **worktree** |  |
| **创建时间** | 2026-04-12 |
| **分支** | $task_slug |

**依赖**：
- 无

**做什么**：Test task

---

## 🎯 关键产品决策

本 task 无关键产品决策（fixture）。

---

## 📐 产物预览

无（基础设施 task）

---

## 📋 功能清单

无（基础设施 task）

---

## 📦 范围

**改**
- test.txt

**不改**
- 其他全部

---

## ✅ 验收清单（PM 走查）

### 主路径
- [ ] 完成

---

## 📁 历史档案（验收时打开看最新一轮）

### 执行日志（agent 填写，不要删除历史记录）

无

---

### PM 反馈（orchestrator 代为追加，agent 重跑前必读）

无
EOF

  # 工程合同（§10 文档偏差 / §11 自审记录 是 parser read_section 的目标）
  cat >"$eng_file" <<EOF
# Task $task_num Engineering: $name

> 本文件是工程合同。PM 视图见 [\`${task_slug}.md\`](./${task_slug}.md)。

- 关联文件：\`${task_slug}.md\`
- 创建时间：2026-04-12

<!-- synced_pm_view_hash: deadbeefcafe -->

---

## 1. 元信息扩展

**executor：** claude-code
**executor_model：**
**审查工具：** $review_tools

---

## 3. 启动前必读

1. docs/modules/test.md

---

## 4. 功能清单工程版

无（fixture）

---

## 5. 实现指引

无（fixture）

---

## 6. 易错点 / 禁止项

| # | 禁止行为 | 后果 / 理由 | 来源 |
|---|---|---|---|

---

## 9. 工程层验收清单

- [ ] 完成

---

## 10. 文档偏差

无偏差

---

## 11. 自审记录

### 自审 1 - 2026-04-12 10:00
**工具：** $review_tools
**结果：** pass
**详细发现：** 无
**遗留问题：** 无
EOF

  # Commit both files to req branch so task worktree sees them
  if [ -n "$req_worktree_root" ] && [ -d "$req_worktree_root/.git" ] || [ -f "$req_worktree_root/.git" ]; then
    (
      cd "$req_worktree_root"
      git add -A 2>/dev/null
      git commit -q -m "create $task_slug (v2)" 2>/dev/null || true
    )
  fi

  echo "$task_file"
}

# v3 单文件 typed contract fixture（delta-3 —— 单文件三区：PM 确认区 / 执行区 / 审计区）
# Usage: fixture_create_task_v3 <req-dir> <task-num> <name> <status> [review_tools] [module]
fixture_create_task_v3() {
  local req_dir="$1"
  local task_num="$2"
  local name="$3"
  local status="${4:-待执行}"
  local review_tools="${5:-/qa}"
  local module="${6:-基础设施}"
  local task_slug="task-${task_num}-${name}"
  local task_file="$req_dir/tasks/${task_slug}.md"

  # req_dir 在某个 req worktree 里。找到 worktree 根
  local req_worktree_root="$req_dir"
  while [ "$req_worktree_root" != "/" ] && [ ! -d "$req_worktree_root/.git" ] && [ ! -f "$req_worktree_root/.git" ]; do
    req_worktree_root=$(dirname "$req_worktree_root")
  done

  cat >"$task_file" <<EOF
# Task $task_num: $name

<!-- task_format: single-typed-v3 -->

<!-- region: PM-CONFIRM begin -->

## 📌 任务卡

| | |
|---|---|
| **状态** | $status |
| **所属模块** | $module |
| **所属模块章节** |  |
| **executor** | claude-code |
| **executor_model** |  |
| **审查工具** | $review_tools |
| **dev server** |  |
| **worktree** |  |
| **创建时间** | 2026-04-12 |
| **分支** | $task_slug |

**依赖**：
- 无

**做什么**（10 秒理解）：Test task

---

## 📦 范围（改 / 不改）

**改**
- test.txt

**不改**
- 其他全部

---

## ✅ 验收清单（PM 走查）

### 主路径
- [ ] 完成

---

## 📥 PM 反馈承接清单

无前序 PM 反馈

<!-- region: PM-CONFIRM end -->

<!-- region: EXEC begin -->

## 🔁 状态转换说明（agent 必读）

| 状态 | 谁行动 | 做什么 |
|------|--------|--------|
| \`待执行\` | orchestrator | 等 PM 通过 \`/task-confirm\` 创建 worktree |

---

## 🚦 启动前必读（按顺序，读完再执行）

1. docs/modules/test.md

---

## 🗂️ 文件范围（机器校验）

- 新建：test.txt
- 修改：无
- 不动：无

---

## 🔧 实现规格

### 1 · Test
Test task spec.

---

## 🧩 实现设计引用（HOW）

| HOW-ID | 决策 / 文件·模式 | 本 task 落地要点 |
|---|---|---|

---

## ⚠️ 约束与易错

| # | 禁止行为 / 易错点 | 后果 / 理由 | 来源 |
|---|---|---|---|

---

## 🧪 自测说明（task 级流程化 UAT，task-verify 自动跑）

无（基础设施 task）

---

## ✔️ 工程层验收（自审用，agent 自动化校验）

- [ ] 完成

<!-- region: EXEC end -->

<!-- region: AUDIT begin -->

## 📋 文档偏差

| 文档位置 | 文档原文 | 实际实现 | 建议改法 |
|---|---|---|---|

无

---

## 🔍 自审记录

### 自审 1 - 2026-04-12 10:00
**工具：** $review_tools
**结果：** pass
**详细发现：** 无
**遗留问题：** 无

---

## 📁 历史档案（验收时打开看最新一轮）

### 执行日志（agent 填写，不要删除历史记录）

无

---

### PM 反馈（orchestrator 代为追加，agent 重跑前必读）

无

<!-- region: AUDIT end -->
EOF

  # Commit task file to req branch so task worktree sees it
  if [ -n "$req_worktree_root" ] && [ -d "$req_worktree_root/.git" ] || [ -f "$req_worktree_root/.git" ]; then
    (
      cd "$req_worktree_root"
      git add -A 2>/dev/null
      git commit -q -m "create $task_slug (v3)" 2>/dev/null || true
    )
  fi

  echo "$task_file"
}

# Create a task worktree + branch (off a req branch)
# Usage: fixture_create_task_worktree <task-file> <req-branch>
fixture_create_task_worktree() {
  local task_file="$1"
  local req_branch="$2"
  local task_stem=$(basename "$task_file" .md)

  (
    cd "$FIXTURE_DIR"
    git worktree add -q -b "$task_stem" ".worktrees/$task_stem" "$req_branch"
  )

  # Update task file's worktree field
  local wt_path=".worktrees/$task_stem"
  # Use sed to update field
  if grep -q '^\*\*worktree：\*\*' "$task_file"; then
    sed -i.bak "s|^\*\*worktree：\*\*.*|\*\*worktree：\*\* $wt_path|" "$task_file"
    rm -f "$task_file.bak"
  fi

  echo "$FIXTURE_DIR/.worktrees/$task_stem"
}

# Make a fake review_completed event in task events stream
# Usage: fixture_add_review_event <task-file> <tool> <result>
fixture_add_review_event() {
  local task_file="$1"
  local tool="$2"
  local result="${3:-pass}"
  local task_stem=$(basename "$task_file" .md)
  local events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  mkdir -p "$(dirname "$events_file")"
  echo "{\"event\":\"review_completed\",\"timestamp\":\"2026-04-12T10:00:00+08:00\",\"task\":\"$task_stem\",\"tool\":\"$tool\",\"result\":\"$result\"}" >> "$events_file"
}

# Seed a full valid event stream that satisfies I-CT7 + I-CT8.
# Timestamps chosen far in the past (2020-01-01...) so any test-time commit
# is guaranteed to be later → I-CT8 passes.
# Usage: fixture_seed_full_event_stream <task-file>
fixture_seed_full_event_stream() {
  local task_file="$1"
  local task_stem
  task_stem=$(basename "$task_file" .md)
  local events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  mkdir -p "$(dirname "$events_file")"
  {
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2020-01-01T00:00:00+00:00\",\"task\":\"$task_stem\",\"from\":\"待执行\",\"to\":\"执行中\"}"
    echo "{\"event\":\"execution_started\",\"timestamp\":\"2020-01-01T00:01:00+00:00\",\"task\":\"$task_stem\",\"executor\":\"claude-code\"}"
    echo "{\"event\":\"status_changed\",\"timestamp\":\"2020-01-01T00:20:00+00:00\",\"task\":\"$task_stem\",\"from\":\"执行中\",\"to\":\"已完成\"}"
  } > "$events_file"
}

# Seed a single execution_started event so the accept gate
# (执行中→已完成 in task-transition.py check_preconditions) passes.
# Use for transition tests that drive a task to 已完成 and expect success.
# Usage: fixture_seed_execution_started <task-file>
fixture_seed_execution_started() {
  local task_file="$1"
  local task_stem
  task_stem=$(basename "$task_file" .md)
  local events_file="$FIXTURE_DIR/.runs/events/${task_stem}.jsonl"
  mkdir -p "$(dirname "$events_file")"
  echo "{\"event\":\"execution_started\",\"timestamp\":\"2020-01-01T00:01:00+00:00\",\"task\":\"$task_stem\",\"executor\":\"claude-code\"}" >> "$events_file"
}
