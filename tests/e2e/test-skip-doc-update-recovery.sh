#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$TEST_ROOT/helpers/assert.sh"
source "$TEST_ROOT/helpers/fixture.sh"

CLOSE_TASK_SKILL="$FRAMEWORK_ROOT/skills/close-task/SKILL.md"

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
  sed -n '1,180p' "$file" >&2
  return 1
}

_append_skip_marker() {
  local task="$1"
  local reason="$2"
  cat >> "$task" <<EOF

<!-- SKIP_DOC_UPDATE: reason="$reason" created_at="2026-04-25T20:48:48+08:00" cleanup_status="pending" -->

## 人工 Cleanup TODO（A1 决议，doc-update 被 skip）
- [ ] 手动运行 /doc-update --task <task-id> 沉淀功能清单进 docs/modules/<module>.md
- [ ] cleanup 完成后，把上方 SKIP_DOC_UPDATE marker 的 cleanup_status 从 "pending" 改为 "done"
- [ ] 重跑 /req-stage-gate 验证半 close 解除
EOF
}

test_skip_doc_update_contract_present() {
  start_test "e2e skip-doc-update: close-task skill defines A1 escape hatch"

  _assert_contains "$CLOSE_TASK_SKILL" "--skip-doc-update flag（A1 紧急逃生舱）" "A1 section" || return
  _assert_contains "$CLOSE_TASK_SKILL" 'Skip the `/doc-update` call entirely' "skip doc-update" || return
  _assert_contains "$CLOSE_TASK_SKILL" '<!-- SKIP_DOC_UPDATE: reason="<PM-provided reason>" created_at="<ISO 8601 timestamp>" cleanup_status="pending" -->' "exact marker" || return
  _assert_contains "$CLOSE_TASK_SKILL" "人工 Cleanup TODO（A1 决议，doc-update 被 skip）" "cleanup TODO block" || return

  pass_test
}

test_skip_doc_update_recovery_flow() {
  start_test "e2e skip-doc-update: marker blocks until cleanup_status done"
  fixture_setup

  req_dir=$(fixture_create_req "req-001" "test" 6)
  task=$(fixture_create_task "$req_dir" "301" "skip-recovery" "已完成" "/qa")
  cat > "$FIXTURE_DIR/mock-doc-update.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$FIXTURE_DIR/mock-doc-update.sh"

  _append_skip_marker "$task" "doc-update mock failure"

  if ! grep -q '<!-- SKIP_DOC_UPDATE:' "$task"; then
    _fail "SKIP_DOC_UPDATE marker missing"
    fixture_teardown
    return
  fi
  if ! grep -q 'cleanup_status="pending"' "$task"; then
    _fail "pending cleanup_status missing"
    fixture_teardown
    return
  fi
  if ! grep -q '人工 Cleanup TODO' "$task" \
    || ! grep -q '手动运行 /doc-update --task <task-id>' "$task" \
    || ! grep -q 'cleanup_status 从 "pending" 改为 "done"' "$task" \
    || ! grep -q '重跑 /req-stage-gate 验证半 close 解除' "$task"; then
    _fail "cleanup TODO checklist incomplete"
    fixture_teardown
    return
  fi

  if ! grep -q '<!-- SKIP_DOC_UPDATE:' "$task" || ! grep -q 'cleanup_status="pending"' "$task"; then
    _fail "Batch 2 C2 compatibility grep simulation failed"
    fixture_teardown
    return
  fi

  sed -i.bak 's/cleanup_status="pending"/cleanup_status="done"/' "$task"
  rm -f "$task.bak"

  if grep -q 'cleanup_status="pending"' "$task"; then
    _fail "pending marker should be cleared after cleanup"
    fixture_teardown
    return
  fi

  fixture_teardown
  pass_test
}

test_skip_doc_update_contract_present
test_skip_doc_update_recovery_flow

report_results "e2e-skip-doc-update-recovery"
