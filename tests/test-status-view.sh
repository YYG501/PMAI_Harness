#!/usr/bin/env bash
# Tests for status-view.py after task pipeline removal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_VIEW="$REPO_ROOT/scripts/status-view.py"
STATUS_SKILL="$REPO_ROOT/skills/status/SKILL.md"

test_summary_lists_active_work() {
  start_test "summary: lists active work by stage, no task wording"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --summary 2>&1)
  if echo "$out" | grep -q "active work" \
     && echo "$out" | grep -q "work-001" \
     && ! echo "$out" | grep -qi "task"; then
    pass_test
  else
    _fail "summary output unexpected: $out"
  fi
  fixture_teardown
}

test_status_suggests_build_not_task() {
  start_test "status: build stage suggests /pmai-build path, no /pmai-task command"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" 2>&1)
  if echo "$out" | grep -q "当前进度：build" \
     && echo "$out" | grep -q "/pmai-build" \
     && ! echo "$out" | grep -q "/pmai-task" \
     && ! echo "$out" | grep -q "Stage："; then
    pass_test
  else
    _fail "status output unexpected: $out"
  fi
  fixture_teardown
}

test_banner_only_renders_active_work() {
  start_test "banner-only: active work renders without task dependency"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out rc
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --banner-only --skill status 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] && echo "$out" | grep -q "status" && echo "$out" | grep -q "build"; then
    pass_test
  else
    _fail "banner-only failed rc=$rc out=$out"
  fi
  fixture_teardown
}

test_timeline_has_no_task_counts() {
  start_test "timeline: no task counts"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --timeline 2>&1)
  if echo "$out" | grep -q "Active" && ! echo "$out" | grep -qi "task"; then
    pass_test
  else
    _fail "timeline output unexpected: $out"
  fi
  fixture_teardown
}

test_narrative_dirty_main_has_pm_action() {
  start_test "narrative: 无 active 但有未提交改动时先给 PM 收口动作"
  fixture_setup
  mkdir -p "$FIXTURE_DIR/Sources"
  echo "print(\"dirty\")" > "$FIXTURE_DIR/Sources/Foo.swift"

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "当前状态：有一轮改动还没收口" \
     && echo "$out" | grep -q "建议下一步：先把这轮改动固定到独立分支或提交点" \
     && ! echo "$out" | grep -q "active work" \
     && ! echo "$out" | grep -q "PMAI 状态脚本"; then
    pass_test
  else
    _fail "dirty main narrative unexpected: $out"
  fi
  fixture_teardown
}

test_narrative_multiple_active_work_pm_view() {
  start_test "narrative: 多个进行中工作按 PM 视图列状态和下一步"
  fixture_setup
  fixture_create_work "work-001" "import" 2 >/dev/null
  fixture_create_work "work-002" "bubble" 1 >/dev/null

  local out
  out=$(cd "$FIXTURE_DIR" && python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "当前状态：有 2 个进行中的工作" \
     && echo "$out" | grep -q "进行中的工作：" \
     && echo "$out" | grep -q "1. import" \
     && echo "$out" | grep -q "2. bubble" \
     && echo "$out" | grep -q "下一步：" \
     && ! echo "$out" | grep -q "active work" \
     && ! echo "$out" | grep -q "Worktree"; then
    pass_test
  else
    _fail "multiple active narrative unexpected: $out"
  fi
  fixture_teardown
}

test_status_skill_blocks_internal_diagnostics() {
  start_test "status skill: 禁止把内部诊断当 PM 现状汇报"

  assert_file_contains "$STATUS_SKILL" "当前状态：有 <N> 个进行中的工作" "status skill should define multi-work PM output" || return
  assert_file_contains "$STATUS_SKILL" "禁止输出“PMAI 状态脚本显示”" "status skill should ban script-diagnostic phrasing" || return
  assert_file_contains "$STATUS_SKILL" "有未提交改动就说“有一轮改动还没收口”" "status skill should collapse dirty-state conflict into PM action" || return
  pass_test
}

test_summary_lists_active_work
test_status_suggests_build_not_task
test_banner_only_renders_active_work
test_timeline_has_no_task_counts
test_narrative_dirty_main_has_pm_action
test_narrative_multiple_active_work_pm_view
test_status_skill_blocks_internal_diagnostics

report_results "status-view"
