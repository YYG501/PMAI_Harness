#!/usr/bin/env bash
# pmai whats-new output contract tests.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

run_whats_new() {
  local state="$1"
  shift
  PMAI_HOME="$REPO_ROOT" PMAI_STATE="$state" bash "$REPO_ROOT/bin/pmai" whats-new "$@"
}

test_versions_do_not_double_prefix_v() {
  start_test "whats-new: v-prefixed versions do not render vv"

  local tmp out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/whats-new.XXXXXX")
  out=$(run_whats_new "$tmp" --from v0.2.0 --to v0.2.1 --max-lines 1 2>&1)
  if echo "$out" | grep -q "vv0"; then
    _fail "输出不应包含 vv 版本前缀"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q "PMAI v0.2.1 — upgraded from v0.2.0"; then
    _fail "输出应保留单个 v 前缀"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_plain_versions_get_one_prefix() {
  start_test "whats-new: plain versions render with one v"

  local tmp out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/whats-new.XXXXXX")
  out=$(run_whats_new "$tmp" --from 0.2.0 --to 0.2.1 --max-lines 1 2>&1)
  if ! echo "$out" | grep -q "PMAI v0.2.1 — upgraded from v0.2.0"; then
    _fail "无 v 输入也应展示为单个 v"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_output_limit_is_visible() {
  start_test "whats-new: default output cap is explicit"

  local tmp out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/whats-new.XXXXXX")
  out=$(run_whats_new "$tmp" --from v0.2.0 --to v0.2.1 --max-lines 1 2>&1)
  if ! echo "$out" | grep -q "默认最多显示 1 行"; then
    _fail "输出应说明 max-lines 上限"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_invalid_max_lines_fails_cleanly() {
  start_test "whats-new: invalid --max-lines fails cleanly"

  local tmp out rc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/whats-new.XXXXXX")
  out=$(run_whats_new "$tmp" --from v0.2.0 --max-lines nope 2>&1)
  rc=$?
  if [ "$rc" != "2" ]; then
    _fail "非法 --max-lines 应 exit 2"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  if ! echo "$out" | grep -q -- "--max-lines 必须是正整数"; then
    _fail "非法 --max-lines 应有可读错误"
    echo "$out" >&2
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_versions_do_not_double_prefix_v
test_plain_versions_get_one_prefix
test_output_limit_is_visible
test_invalid_max_lines_fails_cleanly

report_results "whats-new"
