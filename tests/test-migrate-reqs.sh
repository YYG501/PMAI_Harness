#!/usr/bin/env bash
# migrate-reqs-to-6step.py 回归：旧 7-stage req stage 值重映射到六步（解越界）。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$SCRIPT_DIR"
source "$TEST_ROOT/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATE="$FRAMEWORK_ROOT/scripts/migrate-reqs-to-6step.py"

echo "▶ Running test-migrate-reqs.sh"
echo "─────────────────────────────────────────"

_setup() {
  T=$(mktemp -d)
  mkdir -p "$T/requirements/closed/req-001-old" \
           "$T/requirements/active/req-002-inflight" \
           "$T/requirements/active/req-003-new"
  echo '{"stage": 7, "stage_history": [{"stage":7}]}' > "$T/requirements/closed/req-001-old/.req-meta.json"
  echo '{"stage": 6, "stage_history": [{"stage":5},{"stage":6}]}' > "$T/requirements/active/req-002-inflight/.req-meta.json"
  echo '{"stage": 2, "stage_history": [{"stage":1},{"stage":2}]}' > "$T/requirements/active/req-003-new/.req-meta.json"
}
_teardown() { rm -rf "$T"; }
_stage() { python3 -c "import json;print(json.load(open('$1'))['stage'])"; }
_field() { python3 -c "import json;print(json.load(open('$1')).get('$2',''))"; }

test_remap_legacy() {
  start_test "migrate: 越界值重映射（7→4 / 6→2），新六步 req 不动"
  _setup
  python3 "$MIGRATE" "$T" >/dev/null 2>&1
  local s7 s6 s2 m2
  s7=$(_stage "$T/requirements/closed/req-001-old/.req-meta.json")
  s6=$(_stage "$T/requirements/active/req-002-inflight/.req-meta.json")
  s2=$(_stage "$T/requirements/active/req-003-new/.req-meta.json")
  m2=$(_field "$T/requirements/active/req-003-new/.req-meta.json" migrated_from_7stage)
  if [ "$s7" = "4" ] && [ "$s6" = "2" ] && [ "$s2" = "2" ] && [ -z "$m2" ]; then
    pass_test
  else
    _fail "remap 错：closed=$s7(期4) inflight=$s6(期2) new=$s2(期2,migrated='$m2' 期空)"
  fi
  _teardown
}

test_marks_provenance() {
  start_test "migrate: 迁移的 req 带 migrated_from_7stage 溯源"
  _setup
  python3 "$MIGRATE" "$T" >/dev/null 2>&1
  local m
  m=$(_field "$T/requirements/closed/req-001-old/.req-meta.json" migrated_from_7stage)
  [ "$m" = "7" ] && pass_test || _fail "migrated_from_7stage 应=7，实='$m'"
  _teardown
}

test_idempotent() {
  start_test "migrate: 幂等（再跑不重复迁移 / 不改已迁移值）"
  _setup
  python3 "$MIGRATE" "$T" >/dev/null 2>&1
  local out s7
  out=$(python3 "$MIGRATE" "$T" 2>&1)
  s7=$(_stage "$T/requirements/closed/req-001-old/.req-meta.json")
  if echo "$out" | grep -q "没有需要迁移" && [ "$s7" = "4" ]; then
    pass_test
  else
    _fail "幂等失败：out=$out s7=$s7"
  fi
  _teardown
}

test_dry_run_no_write() {
  start_test "migrate: --dry-run 不写盘"
  _setup
  python3 "$MIGRATE" "$T" --dry-run >/dev/null 2>&1
  local s7
  s7=$(_stage "$T/requirements/closed/req-001-old/.req-meta.json")
  [ "$s7" = "7" ] && pass_test || _fail "dry-run 不该写，stage 应仍=7，实=$s7"
  _teardown
}

test_remap_legacy
test_marks_provenance
test_idempotent
test_dry_run_no_write

report_results "migrate-reqs"
