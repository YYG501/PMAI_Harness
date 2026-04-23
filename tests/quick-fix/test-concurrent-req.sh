#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

test_active_req_warns_but_merges() {
  start_test "scenario 7 active req warns and ff-only succeeds"
  fixture_setup
  fixture_create_req "req-001" "test" 6 >/dev/null
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo warn > docs/warn.md" QUICK_FIX_APPROVE=1 bash "$QF" "warn active" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$) \
    && [ -f "$FIXTURE_DIR/docs/warn.md" ] \
    && grep -q "活跃 req" /tmp/qf.err.$$; then
    pass_test
  else
    _fail "active req warn path failed"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_ff_only_rebase_retry_success() {
  start_test "scenario 8 ff-only failure rebases and retries"
  fixture_setup
  cmd='mkdir -p docs && echo quick > docs/quick-rebase.md && echo main > "$FIXTURE_DIR/docs/main-advance.md" && git -C "$FIXTURE_DIR" add docs/main-advance.md && git -C "$FIXTURE_DIR" commit -q -m "advance main"'
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="$cmd" QUICK_FIX_APPROVE=1 bash "$QF" "rebase retry" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$) \
    && [ -f "$FIXTURE_DIR/docs/quick-rebase.md" ] \
    && [ -f "$FIXTURE_DIR/docs/main-advance.md" ] \
    && grep -q "rebase 后已合并" /tmp/qf.out.$$; then
    pass_test
  else
    _fail "rebase retry should succeed"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_rebase_conflict_keeps_worktree() {
  start_test "scenario 9 rebase conflict keeps worktree"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/docs"
  echo base > "$FIXTURE_DIR/docs/conflict.md"
  (cd "$FIXTURE_DIR" && git add docs/conflict.md && git commit -q -m "add conflict base")
  cmd='echo quick > docs/conflict.md && echo main > "$FIXTURE_DIR/docs/conflict.md" && git -C "$FIXTURE_DIR" add docs/conflict.md && git -C "$FIXTURE_DIR" commit -q -m "conflicting main"'
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="$cmd" QUICK_FIX_APPROVE=1 bash "$QF" "rebase conflict" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$); then
    _fail "rebase conflict should fail"
  elif grep -q "worktree 保留" /tmp/qf.err.$$ && find "$FIXTURE_DIR/.worktrees" -maxdepth 1 -type d -name 'tmp-quick-*' | grep -q tmp-quick; then
    pass_test
  else
    _fail "conflict did not preserve worktree"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_same_second_unique_branches() {
  start_test "scenario 10 two quick-fixes have unique tmp branches"
  fixture_setup
  ok=true
  (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo one > docs/one.md" QUICK_FIX_APPROVE=1 bash "$QF" "one" >/tmp/qf1.out.$$ 2>/tmp/qf1.err.$$) || ok=false
  (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo two > docs/two.md" QUICK_FIX_APPROVE=1 bash "$QF" "two" >/tmp/qf2.out.$$ 2>/tmp/qf2.err.$$) || ok=false
  branches=$(git -C "$FIXTURE_DIR" log --grep '^\[quick-fix\]' --format=%B -4 | awk -F': ' '/临时分支:/ {print $2}' | sort -u | wc -l | tr -d ' ')
  if [ "$ok" = true ] && [ "$branches" -ge 2 ]; then
    pass_test
  else
    _fail "tmp branch names were not unique"
    cat /tmp/qf1.out.$$ /tmp/qf1.err.$$ /tmp/qf2.out.$$ /tmp/qf2.err.$$ >&2
  fi
  rm -f /tmp/qf1.out.$$ /tmp/qf1.err.$$ /tmp/qf2.out.$$ /tmp/qf2.err.$$
  fixture_teardown
}

test_active_req_warns_but_merges
test_ff_only_rebase_retry_success
test_rebase_conflict_keeps_worktree
test_same_second_unique_branches
report_results "quick-fix concurrent req"
