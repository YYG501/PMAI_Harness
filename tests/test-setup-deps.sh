#!/usr/bin/env bash
# Tests for scripts/_setup-deps.sh::setup_dependency_symlinks
#
# Regression for: 主仓根没有 package.json 时（子目录项目模式如 prototypes/、
# apps/web/、packages/foo/），原实现整个 setup 空转，worktree 拿不到任何
# node_modules symlink — codex/cursor-agent 跑测试全失败。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$FRAMEWORK_ROOT/scripts/_setup-deps.sh"

PASS=0
FAIL=0
FAILURES=()

pass_test() { PASS=$((PASS + 1)); echo "  ✅ $CURRENT_TEST"; }
fail_test() {
  FAIL=$((FAIL + 1))
  FAILURES+=("$CURRENT_TEST: $*")
  echo "  ❌ $CURRENT_TEST: $*"
}
start_test() { CURRENT_TEST="$1"; echo "  RUN  $1"; }

report_results() {
  echo ""
  echo "═════════════════════════════════════════"
  echo "  Suite: setup-deps"
  echo "  Passed: $PASS"
  echo "  Failed: $FAIL"
  echo "═════════════════════════════════════════"
  if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "Failures:"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
    exit 1
  fi
}

make_fixture() {
  REPO=$(mktemp -d "${TMPDIR:-/tmp}/setupdeps-repo.XXXXXX")
  WT=$(mktemp -d "${TMPDIR:-/tmp}/setupdeps-wt.XXXXXX")
}

teardown_fixture() {
  rm -rf "$REPO" "$WT"
}

# Assert that $WT/<rel>/node_modules is a symlink resolving to $REPO/<rel>/node_modules.
assert_linked() {
  local rel="$1"
  local link="$WT${rel:+/$rel}/node_modules"
  local target="$REPO${rel:+/$rel}/node_modules"
  if [ ! -L "$link" ]; then
    fail_test "$link 不是 symlink"; return 1
  fi
  local resolved
  resolved=$(readlink "$link")
  if [ "$resolved" != "$target" ]; then
    fail_test "$link → $resolved，期望 $target"; return 1
  fi
  return 0
}

# ----------------------------------------------------------------------
# 回归：子目录项目（根没 package.json，prototypes/ 有）— ExampleConsumerApp 模式
# ----------------------------------------------------------------------
test_subdir_project_links_node_modules() {
  start_test "子目录项目：根无 package.json，prototypes/node_modules 仍被 link"
  make_fixture
  mkdir -p "$REPO/prototypes/node_modules"
  echo '{}' > "$REPO/prototypes/package.json"
  # 主仓根故意不放 package.json
  setup_dependency_symlinks "$REPO" "$WT"
  if assert_linked "prototypes"; then pass_test; fi
  teardown_fixture
}

# ----------------------------------------------------------------------
# 回归：根级项目（保护原行为不破坏）
# ----------------------------------------------------------------------
test_root_project_links_node_modules() {
  start_test "根级项目：根 package.json + node_modules 正常被 link"
  make_fixture
  echo '{}' > "$REPO/package.json"
  mkdir -p "$REPO/node_modules"
  setup_dependency_symlinks "$REPO" "$WT"
  if assert_linked ""; then pass_test; fi
  teardown_fixture
}

# ----------------------------------------------------------------------
# Monorepo：根 + apps/web + packages/foo 多包都 link
# ----------------------------------------------------------------------
test_monorepo_all_packages_linked() {
  start_test "monorepo：根 + apps/web + packages/foo 全部 link 同目录 node_modules"
  make_fixture
  mkdir -p "$REPO/node_modules" "$REPO/apps/web/node_modules" "$REPO/packages/foo/node_modules"
  echo '{}' > "$REPO/package.json"
  echo '{}' > "$REPO/apps/web/package.json"
  echo '{}' > "$REPO/packages/foo/package.json"
  setup_dependency_symlinks "$REPO" "$WT"
  local ok=1
  assert_linked "" || ok=0
  assert_linked "apps/web" || ok=0
  assert_linked "packages/foo" || ok=0
  [ "$ok" = "1" ] && pass_test
  teardown_fixture
}

# ----------------------------------------------------------------------
# 边界：package.json 存在但同目录 node_modules 不存在 → 不创建 broken link
# ----------------------------------------------------------------------
test_missing_node_modules_skipped() {
  start_test "package.json 在但 node_modules 不在 → 不创建 broken symlink"
  make_fixture
  mkdir -p "$REPO/prototypes"
  echo '{}' > "$REPO/prototypes/package.json"
  # 故意不建 prototypes/node_modules
  setup_dependency_symlinks "$REPO" "$WT"
  if [ -e "$WT/prototypes/node_modules" ] || [ -L "$WT/prototypes/node_modules" ]; then
    fail_test "不应创建任何 link / 目录，实际产生了 $WT/prototypes/node_modules"
  else
    pass_test
  fi
  teardown_fixture
}

# ----------------------------------------------------------------------
# Prune：嵌套 node_modules/pkg/package.json 不被遍历（不会 link 嵌套层）
# ----------------------------------------------------------------------
test_nested_node_modules_pruned() {
  start_test "嵌套 node_modules/<pkg>/package.json 被 prune，不会被 link"
  make_fixture
  echo '{}' > "$REPO/package.json"
  mkdir -p "$REPO/node_modules/somepkg"
  echo '{"name":"somepkg"}' > "$REPO/node_modules/somepkg/package.json"
  setup_dependency_symlinks "$REPO" "$WT"
  # 根级 link 应该有
  assert_linked "" || true
  # 嵌套层不应在 worktree 里产生 node_modules/somepkg/node_modules
  if [ -L "$WT/node_modules/somepkg/node_modules" ] || [ -d "$WT/node_modules/somepkg/node_modules" ]; then
    fail_test "嵌套层被错误地 link 了"
  else
    pass_test
  fi
  teardown_fixture
}

# ----------------------------------------------------------------------
# Prune：.worktrees / .git / .next / dist / build 不被遍历
# ----------------------------------------------------------------------
test_pruned_dirs_ignored() {
  start_test ".worktrees/.git/.next/dist/pmai-build 里的 package.json 全部被 prune"
  make_fixture
  echo '{}' > "$REPO/package.json"
  mkdir -p "$REPO/node_modules"
  for d in .worktrees/wt-1 .next/types dist/foo build/bar .git/sub; do
    mkdir -p "$REPO/$d"
    echo '{}' > "$REPO/$d/package.json"
    mkdir -p "$REPO/$d/node_modules"
  done
  setup_dependency_symlinks "$REPO" "$WT"
  local leaked=""
  for d in .worktrees/wt-1 .next/types dist/foo build/bar .git/sub; do
    if [ -e "$WT/$d/node_modules" ]; then leaked="$leaked $d"; fi
  done
  if [ -n "$leaked" ]; then
    fail_test "下列被 prune 路径漏到 worktree:$leaked"
  else
    pass_test
  fi
  teardown_fixture
}

echo "▶ Running test-setup-deps.sh"
echo "─────────────────────────────────────────"

test_subdir_project_links_node_modules
test_root_project_links_node_modules
test_monorepo_all_packages_linked
test_missing_node_modules_skipped
test_nested_node_modules_pruned
test_pruned_dirs_ignored

report_results
