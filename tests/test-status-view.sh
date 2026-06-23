#!/usr/bin/env bash
# Tests for status-view.py after task pipeline removal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_VIEW="$REPO_ROOT/scripts/status-view.py"

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
  if echo "$out" | grep -q "build 阶段" \
     && echo "$out" | grep -q "/pmai-build" \
     && ! echo "$out" | grep -q "/pmai-task"; then
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

test_summary_lists_active_work
test_status_suggests_build_not_task
test_banner_only_renders_active_work
test_timeline_has_no_task_counts

report_results "status-view"
