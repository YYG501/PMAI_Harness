#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TEST_ROOT/helpers/assert.sh"
source "$TEST_ROOT/helpers/fixture.sh"

DOC_UPDATE_SKILL="$FRAMEWORK_ROOT/skills/doc-update/SKILL.md"

_contains() {
  local file="$1"
  local text="$2"
  grep -F -q -- "$text" "$file"
}

_assert_contains() {
  local file="$1"
  local text="$2"
  local desc="$3"
  if _contains "$file" "$text"; then
    return 0
  fi
  _fail "$desc: missing '$text'"
  sed -n '110,230p' "$file" >&2
  return 1
}

test_failure_blocks_close_task_contract() {
  start_test "e2e failure recovery: doc-update failure blocks close-task"

  _assert_contains "$DOC_UPDATE_SKILL" "ALL failures block close-task" "all failures block close-task" || return
  _assert_contains "$DOC_UPDATE_SKILL" "失败时必须停止并返回错误报告" "stop on failure" || return
  _assert_contains "$DOC_UPDATE_SKILL" "沉淀失败时不得继续 close-task" "must not continue close-task" || return

  pass_test
}

test_error_message_format_complete() {
  start_test "e2e failure recovery: error message covers file/type/recovery"

  _assert_contains "$DOC_UPDATE_SKILL" '`文件`：具体失败文件' "file field" || return
  _assert_contains "$DOC_UPDATE_SKILL" '`failure type`：只能使用 `write-file` / `content-conflict` / `key-match-failure` / `internal-bug`' "failure types" || return
  _assert_contains "$DOC_UPDATE_SKILL" '`recovery path`：PM 需要怎么修' "recovery path" || return
  _assert_contains "$DOC_UPDATE_SKILL" "doc-update failed; close-task blocked" "example error title" || return
  _assert_contains "$DOC_UPDATE_SKILL" "文件: docs/modules/account.md" "example file" || return
  _assert_contains "$DOC_UPDATE_SKILL" "failure type: key-match-failure" "example type" || return
  _assert_contains "$DOC_UPDATE_SKILL" "recovery path: 修正 task.md 的 **所属模块章节：**" "example recovery" || return

  pass_test
}

test_rerun_auto_resume_contract() {
  start_test "e2e failure recovery: PM fixes then reruns close-task and doc-update resumes"

  _assert_contains "$DOC_UPDATE_SKILL" 'PM 修复 underlying issue 后，重新运行 `/close-task`' "rerun close-task" || return
  _assert_contains "$DOC_UPDATE_SKILL" '`/close-task` 会 auto-resumes doc-update' "auto-resume doc-update" || return
  _assert_contains "$DOC_UPDATE_SKILL" "系统会自动续跑 doc-update" "example auto resume" || return

  pass_test
}

test_atomic_rollback_contract() {
  start_test "e2e failure recovery: multi-module failure leaves no intermediate state"

  _assert_contains "$DOC_UPDATE_SKILL" "Any failure → delete temp branch → block close-task + error report" "delete temp branch on failure" || return
  _assert_contains "$DOC_UPDATE_SKILL" "当前 req 分支保持原 HEAD，不留下中间写入状态" "no intermediate writes" || return

  pass_test
}

test_failure_blocks_close_task_contract
test_error_message_format_complete
test_rerun_auto_resume_contract
test_atomic_rollback_contract

report_results "e2e-doc-update-failure-recovery"
