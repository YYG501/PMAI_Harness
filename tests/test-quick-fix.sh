#!/usr/bin/env bash
# Tests for /quick-fix — covers core scenarios from docs/archive/design/设计-quick-fix.md v2 §11.
# Scenarios exercised (subset of full 17; rest tracked as future work):
#   - Scenario 1: happy path pure-docs change, ff-only merges, two-commit model visible
#   - Scenario 11: red-line rejects edits to requirements/active/*/tasks/*.md
#   - Scenario 15: --cancel cleans specified tmp-quick-* branch + worktree
#   - Scenario 16: --cleanup removes all residual tmp-quick-* branches
#   - Scenario 17: sanitize_desc strips |/backtick/$/; from commit subject

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QUICK_FIX="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

# ---------- Scenario 1: happy path (docs change) ----------
test_happy_path_docs() {
  start_test "[quick-fix] 场景 1: happy path — 纯文档改 + ff-only + 两 commit"
  fixture_setup
  echo "# Orig" > "$FIXTURE_DIR/docs/SPEC.md"
  (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "add SPEC.md")

  QUICK_FIX_COMMAND='echo "" >> docs/SPEC.md; echo "- line added" >> docs/SPEC.md' \
    QUICK_FIX_APPROVE=1 \
    bash -c "cd '$FIXTURE_DIR' && bash '$QUICK_FIX' 'edit SPEC'" >/tmp/qf.out.$$ 2>&1
  rc=$?

  if [ "$rc" -ne 0 ]; then
    _fail "quick-fix run failed (rc=$rc)"
    cat /tmp/qf.out.$$ >&2
  elif ! (cd "$FIXTURE_DIR" && git log --oneline -1 | grep -q '\[quick-fix-log\]'); then
    _fail "expected [quick-fix-log] as top commit"
  elif ! (cd "$FIXTURE_DIR" && git log --oneline -2 | tail -1 | grep -q '\[quick-fix\]'); then
    _fail "expected [quick-fix] as second-from-top commit"
  elif ! (cd "$FIXTURE_DIR" && grep -q "line added" docs/SPEC.md); then
    _fail "change did not land on main"
  elif (cd "$FIXTURE_DIR" && git branch | grep -q tmp-quick); then
    _fail "tmp-quick-* branch not cleaned up"
  else
    pass_test
  fi
  rm -f /tmp/qf.out.$$
  fixture_teardown
}

# ---------- Scenario 11: red-line rejects tasks/*.md ----------
test_redline_task_file() {
  start_test "[quick-fix] 场景 11: 红线拒绝 requirements/active/*/tasks/*.md"
  fixture_setup
  # 直接在 main 上建一个 active req + task 文件（用于 red-line 事后 diff 检查）
  mkdir -p "$FIXTURE_DIR/requirements/active/req-001-test/tasks"
  cat > "$FIXTURE_DIR/requirements/active/req-001-test/.req-meta.json" <<EOF
{"id":"req-001","name":"test","branch":"req-001-test","stage":5,"stage_history":[],"is_first_req":true,"status":"active"}
EOF
  cat > "$FIXTURE_DIR/requirements/active/req-001-test/tasks/task-001-t.md" <<'EOF'
# Task 001

**状态：** 待执行
EOF
  (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "seed req/task on main")

  QUICK_FIX_COMMAND='echo "hacked" >> requirements/active/req-001-test/tasks/task-001-t.md' \
    QUICK_FIX_APPROVE=1 \
    bash -c "cd '$FIXTURE_DIR' && bash '$QUICK_FIX' 'evil edit'" >/tmp/qf.out.$$ 2>&1
  rc=$?

  if [ "$rc" -eq 0 ]; then
    _fail "quick-fix should have rejected task file edit (rc=0)"
    cat /tmp/qf.out.$$ >&2
  elif grep -q "红线" /tmp/qf.out.$$; then
    pass_test
  else
    _fail "expected red-line rejection message, got:"
    cat /tmp/qf.out.$$ >&2
  fi
  rm -f /tmp/qf.out.$$
  fixture_teardown
}

# ---------- Scenario 15: --cancel cleans a specific branch ----------
test_cancel_specific_branch() {
  start_test "[quick-fix] 场景 15: --cancel 清理指定 tmp-quick-* 分支"
  fixture_setup
  branch="tmp-quick-test-a"
  (cd "$FIXTURE_DIR" && git worktree add -q -b "$branch" ".worktrees/$branch" main)

  (cd "$FIXTURE_DIR" && bash "$QUICK_FIX" --cancel "$branch") >/tmp/qf.out.$$ 2>&1
  rc=$?

  if [ "$rc" -ne 0 ]; then
    _fail "--cancel exited $rc"
    cat /tmp/qf.out.$$ >&2
  elif (cd "$FIXTURE_DIR" && git show-ref --verify --quiet "refs/heads/$branch"); then
    _fail "branch still exists after --cancel"
  elif [ -d "$FIXTURE_DIR/.worktrees/$branch" ]; then
    _fail "worktree dir still exists after --cancel"
  else
    pass_test
  fi
  rm -f /tmp/qf.out.$$
  fixture_teardown
}

# ---------- Scenario 16: --cleanup removes all residues ----------
test_cleanup_all() {
  start_test "[quick-fix] 场景 16: --cleanup 清理所有 tmp-quick-* 残留"
  fixture_setup
  for t in x y z; do
    (cd "$FIXTURE_DIR" && git worktree add -q -b "tmp-quick-$t" ".worktrees/tmp-quick-$t" main)
  done

  QUICK_FIX_ASSUME_YES=1 bash -c "cd '$FIXTURE_DIR' && bash '$QUICK_FIX' --cleanup" >/tmp/qf.out.$$ 2>&1
  rc=$?

  if [ "$rc" -ne 0 ]; then
    _fail "--cleanup exited $rc"
    cat /tmp/qf.out.$$ >&2
  elif (cd "$FIXTURE_DIR" && git branch | grep -q tmp-quick); then
    _fail "tmp-quick-* branches remain after --cleanup"
  else
    pass_test
  fi
  rm -f /tmp/qf.out.$$
  fixture_teardown
}

# ---------- Scenario 17: sanitize_desc ----------
test_sanitize_desc() {
  start_test "[quick-fix] 场景 17: sanitize desc 剥离 |/backtick/\$/;"
  fixture_setup
  echo "# orig" > "$FIXTURE_DIR/docs/T.md"
  (cd "$FIXTURE_DIR" && git add -A && git commit -q -m "seed T")

  evil='foo|bar`cmd`$(nope);extra'
  QUICK_FIX_COMMAND='echo "x" > docs/T.md' \
    QUICK_FIX_APPROVE=1 \
    bash -c "cd '$FIXTURE_DIR' && bash '$QUICK_FIX' \"$evil\"" >/tmp/qf.out.$$ 2>&1
  rc=$?

  if [ "$rc" -ne 0 ]; then
    _fail "quick-fix run failed (rc=$rc)"
    cat /tmp/qf.out.$$ >&2
  else
    # Inspect the [quick-fix] commit subject (2nd from top, since top is [quick-fix-log])
    subj=$(cd "$FIXTURE_DIR" && git log --format=%s -2 | tail -1)
    if echo "$subj" | grep -q '`' ; then
      _fail "backtick not stripped: $subj"
    elif echo "$subj" | grep -q '\$' ; then
      _fail "\$ not stripped: $subj"
    elif echo "$subj" | grep -q ';' ; then
      _fail "; not stripped: $subj"
    elif echo "$subj" | grep -q '|' && ! echo "$subj" | grep -q '｜' ; then
      _fail "raw | not replaced with fullwidth: $subj"
    else
      pass_test
    fi
  fi
  rm -f /tmp/qf.out.$$
  fixture_teardown
}

# ---------- Run all ----------
test_happy_path_docs
test_redline_task_file
test_cancel_specific_branch
test_cleanup_all
test_sanitize_desc
report_results "quick-fix"
