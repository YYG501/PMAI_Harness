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
  touch "$FIXTURE_DIR/docs/CONTEXT.md"
  touch "$FIXTURE_DIR/docs/DESIGN.md"
  touch "$FIXTURE_DIR/docs/prd.md"
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
# Usage: fixture_create_req <req-id> <name> <stage> [is_first_req]
fixture_create_req() {
  local req_id="$1"
  local name="$2"
  local stage="${3:-1}"
  local is_first="${4:-true}"
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
  "is_first_req": $is_first,
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

# Create a fake task in a req's tasks/ dir AND commit it to the req branch
# Usage: fixture_create_task <req-dir> <task-num> <name> <status> [review_tools]
fixture_create_task() {
  local req_dir="$1"
  local task_num="$2"
  local name="$3"
  local status="${4:-待确认}"
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
