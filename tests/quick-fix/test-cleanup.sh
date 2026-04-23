#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

_leftover_branch_from_output() {
  awk '/^BRANCH:/ {print $2}' "$1"
}

test_pm_cancel_cleans() {
  start_test "scenario 14 PM cancel cleans worktree and branch"
  fixture_setup
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo cancel > docs/cancel.md" QUICK_FIX_DECISION=cancel bash "$QF" "cancel me" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$) \
    && ! [ -f "$FIXTURE_DIR/docs/cancel.md" ] \
    && ! git -C "$FIXTURE_DIR" branch --list 'tmp-quick-*' | grep -q tmp-quick; then
    pass_test
  else
    _fail "cancel should clean"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_cancel_subcommand() {
  start_test "scenario 15 --cancel removes specified tmp branch"
  fixture_setup
  (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo redo > docs/redo.md" QUICK_FIX_DECISION=redo bash "$QF" "redo me" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$)
  branch=$(_leftover_branch_from_output /tmp/qf.out.$$)
  if [ -n "$branch" ] \
    && (cd "$FIXTURE_DIR" && bash "$QF" --cancel "$branch" >/tmp/qf-cancel.out.$$ 2>/tmp/qf-cancel.err.$$) \
    && ! git -C "$FIXTURE_DIR" show-ref --verify --quiet "refs/heads/$branch" \
    && ! [ -d "$FIXTURE_DIR/.worktrees/$branch" ]; then
    pass_test
  else
    _fail "--cancel should remove branch/worktree"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ /tmp/qf-cancel.out.$$ /tmp/qf-cancel.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$ /tmp/qf-cancel.out.$$ /tmp/qf-cancel.err.$$
  fixture_teardown
}

test_cleanup_subcommand() {
  start_test "scenario 16 --cleanup removes all tmp quick leftovers"
  fixture_setup
  (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo a > docs/a.md" QUICK_FIX_DECISION=redo bash "$QF" "redo a" >/tmp/qf-a.out.$$ 2>/tmp/qf-a.err.$$)
  (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo b > docs/b.md" QUICK_FIX_DECISION=redo bash "$QF" "redo b" >/tmp/qf-b.out.$$ 2>/tmp/qf-b.err.$$)
  if (cd "$FIXTURE_DIR" && QUICK_FIX_ASSUME_YES=1 bash "$QF" --cleanup >/tmp/qf-clean.out.$$ 2>/tmp/qf-clean.err.$$) \
    && ! git -C "$FIXTURE_DIR" branch --list 'tmp-quick-*' | grep -q tmp-quick \
    && [ -z "$(find "$FIXTURE_DIR/.worktrees" -maxdepth 1 -type d -name 'tmp-quick-*')" ]; then
    pass_test
  else
    _fail "--cleanup should remove leftovers"
    cat /tmp/qf-clean.out.$$ /tmp/qf-clean.err.$$ >&2
  fi
  rm -f /tmp/qf-a.out.$$ /tmp/qf-a.err.$$ /tmp/qf-b.out.$$ /tmp/qf-b.err.$$ /tmp/qf-clean.out.$$ /tmp/qf-clean.err.$$
  fixture_teardown
}

test_pm_cancel_cleans
test_cancel_subcommand
test_cleanup_subcommand
report_results "quick-fix cleanup"
