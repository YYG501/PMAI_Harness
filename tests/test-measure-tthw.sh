#!/usr/bin/env bash
# Static and smoke tests for scripts/measure-tthw.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/measure-tthw.sh"

test_help_documents_two_lanes() {
  start_test "measure-tthw: help documents smoke and dogfood lanes"

  assert_success "measure-tthw --help should succeed" bash "$SCRIPT" --help || return
  assert_file_contains "$SCRIPT" "smoke" "script should keep automated skeleton lane" || return
  assert_file_contains "$SCRIPT" "record" "script should keep human dogfood lane" || return
  assert_file_contains "$SCRIPT" "Do not fake" "script should forbid fake non-interactive first spec timing" || return
  pass_test
}

test_skeleton_smoke_runs_init_and_status() {
  start_test "measure-tthw: skeleton smoke runs init-project + status-view"

  local base fake_home target out rc
  base=$(mktemp -d "${TMPDIR:-/tmp}/measure-tthw.XXXXXX")
  fake_home="$base/home"
  target="$base/MeasuredDemo"
  mkdir -p "$fake_home/.claude/skills/gstack"

  out=$(HOME="$fake_home" \
    GIT_AUTHOR_NAME="PMAI Test" GIT_AUTHOR_EMAIL="pmai-test@example.com" \
    GIT_COMMITTER_NAME="PMAI Test" GIT_COMMITTER_EMAIL="pmai-test@example.com" \
    bash "$SCRIPT" smoke --project-name MeasuredDemo --target-dir "$target" --background "TTHW test" --project-type prototype 2>&1)
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "skeleton smoke 应成功"
    echo "$out" >&2
    rm -rf "$base"
    return
  fi
  if ! echo "$out" | grep -q "TTHW_SKELETON_SECONDS="; then
    _fail "skeleton smoke 应输出 TTHW_SKELETON_SECONDS"
    echo "$out" >&2
    rm -rf "$base"
    return
  fi
  if [ ! -f "$target/AGENTS.md" ]; then
    _fail "skeleton smoke 应生成可识别项目骨架"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_record_writes_tthw_jsonl() {
  start_test "measure-tthw: record writes .pm-workflow/audits/tthw.jsonl"

  local base project out log
  base=$(mktemp -d "${TMPDIR:-/tmp}/measure-tthw-record.XXXXXX")
  project="$base/Demo"
  mkdir -p "$project/docs/modules/orders" "$project/.pm-workflow/audits"
  echo "# Spec" > "$project/docs/modules/orders/spec.md"

  out=$(bash "$SCRIPT" record "$project" \
    --module orders \
    --started-at "2026-07-07T10:00:00+08:00" \
    --ended-at "2026-07-07T10:20:30+08:00" \
    --note "test record" 2>&1)
  if ! echo "$out" | grep -q "TTHW_FIRST_SPEC_SECONDS=1230"; then
    _fail "record 应计算秒数"
    echo "$out" >&2
    rm -rf "$base"
    return
  fi

  log="$project/.pm-workflow/audits/tthw.jsonl"
  if [ ! -f "$log" ]; then
    _fail "record 应写 tthw.jsonl"
    rm -rf "$base"
    return
  fi
  if ! grep -q '"module": "orders"' "$log" || ! grep -q '"spec_exists": true' "$log"; then
    _fail "record JSON 应包含 module 和 spec_exists"
    cat "$log" >&2
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

test_help_documents_two_lanes
test_skeleton_smoke_runs_init_and_status
test_record_writes_tthw_jsonl

report_results "measure-tthw"
