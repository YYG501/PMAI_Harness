# shellcheck shell=bash
# Fixture helpers: build minimal fake project for testing close/cancel/transition logic
#
# Sets up:
#   $FIXTURE_DIR          - temp dir with initialized project
#   $FIXTURE_DIR/.claude/scripts/  - symlinked to real scripts/ for testing
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
  # 真相源 = docs/modules/（lifecycle 迁移批 2/3）。批 3 拆掉 requirements/ 桥接后
  # fixture_setup 不再预建 requirements/active|closed/；仍直接操作老 requirements/closed/
  # 的少数测试（symlink-prd helper unit / sync-prds 兼容老仓）自行 mkdir。
  mkdir -p "$FIXTURE_DIR/.claude"
  mkdir -p "$FIXTURE_DIR/docs/modules"
  mkdir -p "$FIXTURE_DIR/prototypes"
  mkdir -p "$FIXTURE_DIR/.runs/events"
  mkdir -p "$FIXTURE_DIR/.worktrees"

  # Symlink real scripts
  ln -s "$FRAMEWORK_ROOT/scripts" "$FIXTURE_DIR/.claude/scripts"

  # Minimal docs skeleton
  touch "$FIXTURE_DIR/docs/PRODUCT.md"
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
#
# 真相源（lifecycle 迁移批 2/3）= docs/modules/<分支>/.req-meta.json，state.py 单读、
# close/cancel 机器（批 3 重写后）也只认这里。批 2 曾双写一份 requirements/active/<分支>/
# 桥接旧 close/cancel；批 3 把机器改成「清模块 .req-meta」后，requirements/ 半边已拆。
#   模块目录名 = req 分支名（测试不关心模块名派生）。
#   返回 docs/modules/<分支> 路径（close/cancel/symlink 测试把它当 <req-dir> 传入）。
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

  local wt="$FIXTURE_DIR/.worktrees/$req_branch"
  # 真相源（state.py 单读 + close/cancel 批 3 单读）
  local module_dir="$wt/docs/modules/$req_branch"
  mkdir -p "$module_dir"

  # Create meta
  local meta_json
  meta_json=$(cat <<EOF
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
)
  printf '%s\n' "$meta_json" > "$module_dir/.req-meta.json"

  # Create minimal discussion.md（模块三件套之一；占位让 git 有内容可 commit）
  echo "# Discussion" > "$module_dir/discussion.md"

  # Commit on req branch
  (
    cd "$wt"
    git add -A
    git commit -q -m "create $req_id"
  )

  echo "$module_dir"
}
