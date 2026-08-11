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
  # fixture_setup 不再预建 requirements/active|closed/。
  mkdir -p "$FIXTURE_DIR/.claude"
  mkdir -p "$FIXTURE_DIR/docs/modules"
  mkdir -p "$FIXTURE_DIR/prototypes"
  mkdir -p "$FIXTURE_DIR/.runs/events"
  mkdir -p "$FIXTURE_DIR/.worktrees"

  # Symlink real scripts
  ln -s "$FRAMEWORK_ROOT/scripts" "$FIXTURE_DIR/.claude/scripts"

  # Minimal docs skeleton
  write_equivalent_product_baseline "$FIXTURE_DIR"
  touch "$FIXTURE_DIR/DESIGN.md"
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

# Create a fake active build work with meta at given stage.
# Usage: fixture_create_work <work-id> <name> <stage>
# 返回 docs/modules/<分支> 路径。
fixture_create_work() {
  local work_id="$1"
  local name="$2"
  local stage="${3:-1}"
  local work_branch="build-$work_id-$name"

  # Create build worktree on new branch (from main)
  (
    cd "$FIXTURE_DIR"
    git worktree add -q -b "$work_branch" ".worktrees/$work_branch" main
  )

  local wt="$FIXTURE_DIR/.worktrees/$work_branch"
  # 真相源（state.py 单读 + close/cancel 批 3 单读）
  local module_dir="$wt/docs/modules/$work_branch"
  mkdir -p "$module_dir"

  # Create meta
  local meta_json
  meta_json=$(cat <<EOF
{
  "id": "$work_id",
  "name": "$name",
  "branch": "$work_branch",
  "worktree": ".worktrees/$work_branch",
  "stage": $stage,
  "stage_history": [{"stage": 1, "entered_at": "2026-04-12T10:00:00+08:00"}],
  "status": "active",
  "build": {
    "anchor": "docs/modules/$work_branch/spec.md",
    "mode": "worktree",
    "executor": "codex",
    "branch": "$work_branch",
    "worktree": ".worktrees/$work_branch",
    "baseline_sha": "fixture-baseline",
    "audit_dir": ".pm-workflow/audits/$work_branch",
    "started_at": "2026-04-12T10:00:00+08:00",
    "implementation_commit": "fixture-implementation",
    "pm_accepted_at": "2026-04-12T10:30:00+08:00"
  }
}
EOF
)
  printf '%s\n' "$meta_json" > "$module_dir/.work-meta.json"

  # Create minimal discussion.md（模块三件套之一；占位让 git 有内容可 commit）
  echo "# Discussion" > "$module_dir/discussion.md"
  mkdir -p "$wt/.pm-workflow/audits/$work_branch"
  cat > "$wt/.pm-workflow/audits/$work_branch/coverage.json" <<'JSON'
{"items":[{"name":"fixture coverage","status":"built","note":""}]}
JSON
  cat > "$wt/.pm-workflow/audits/$work_branch/browser-smoke.json" <<'JSON'
{"status":"pass","active_browser_smoke":true,"active_design_smoke":false}
JSON
  cat > "$wt/.pm-workflow/audits/$work_branch/visual.json" <<'JSON'
{"status":"pass","findings":[]}
JSON
  cat > "$wt/.pm-workflow/audits/$work_branch/behavior.json" <<'JSON'
{"status":"pass","passed":1,"total":1,"note":""}
JSON
  echo "# Legacy v1 acceptance report" > "$wt/.pm-workflow/audits/$work_branch/synthesis.md"

  # Commit on build branch
  (
    cd "$wt"
    git add -A
    git commit -q -m "create $work_id"
  )

  echo "$module_dir"
}

# Create a fake active build that was done directly on main.
# Usage: fixture_create_main_work <work-id> <name> <stage>
fixture_create_main_work() {
  local work_id="$1"
  local name="$2"
  local stage="${3:-2}"
  local module_name="build-$work_id-$name"
  local module_dir="$FIXTURE_DIR/docs/modules/$module_name"

  mkdir -p "$module_dir"
  local head
  head=$(git -C "$FIXTURE_DIR" rev-parse HEAD)

  local meta_json
  meta_json=$(cat <<EOF
{
  "id": "$work_id",
  "name": "$name",
  "branch": "main",
  "worktree": null,
  "stage": $stage,
  "stage_history": [{"stage": 1, "entered_at": "2026-04-12T10:00:00+08:00"}],
  "status": "active",
  "build": {
    "anchor": "docs/modules/$module_name/spec.md",
    "mode": "main",
    "executor": "codex",
    "branch": "main",
    "worktree": null,
    "baseline_sha": "$head",
    "audit_dir": ".pm-workflow/audits/$module_name",
    "started_at": "2026-04-12T10:00:00+08:00",
    "implementation_commit": "$head",
    "pm_accepted_at": "2026-04-12T10:30:00+08:00"
  }
}
EOF
)
  printf '%s\n' "$meta_json" > "$module_dir/.work-meta.json"
  echo "# Discussion" > "$module_dir/discussion.md"
  mkdir -p "$FIXTURE_DIR/.pm-workflow/audits/$module_name"
  cat > "$FIXTURE_DIR/.pm-workflow/audits/$module_name/coverage.json" <<'JSON'
{"items":[{"name":"fixture coverage","status":"built","note":""}]}
JSON
  cat > "$FIXTURE_DIR/.pm-workflow/audits/$module_name/browser-smoke.json" <<'JSON'
{"status":"pass","active_browser_smoke":true,"active_design_smoke":false}
JSON
  cat > "$FIXTURE_DIR/.pm-workflow/audits/$module_name/visual.json" <<'JSON'
{"status":"pass","findings":[]}
JSON
  cat > "$FIXTURE_DIR/.pm-workflow/audits/$module_name/behavior.json" <<'JSON'
{"status":"pass","passed":1,"total":1,"note":""}
JSON
  echo "# Legacy v1 acceptance report" > "$FIXTURE_DIR/.pm-workflow/audits/$module_name/synthesis.md"

  (
    cd "$FIXTURE_DIR"
    git add -A
    git commit -q -m "create main work $work_id"
  )

  echo "$module_dir"
}
