#!/usr/bin/env bash
# TTHW smoke test: init-project → first status-view-visible req.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEASURE_TTHW="$REPO_ROOT/scripts/measure-tthw.sh"
NEW_REQ_SKILL="$REPO_ROOT/skills/new-req/SKILL.md"

json_value() {
  local json_file="$1"
  local key="$2"
  python3 - "$json_file" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
value = data
for part in sys.argv[2].split("."):
    value = value[part]
print(value)
PY
}

test_contract_is_documented() {
  start_test "T1: /new-req 文档引用 create-req-headless.sh 作为状态创建契约"
  assert_file_exists "$REPO_ROOT/scripts/create-req-headless.sh" || return
  assert_file_exists "$MEASURE_TTHW" || return
  assert_file_contains "$NEW_REQ_SKILL" "create-req-headless.sh" || return
  assert_file_contains "$MEASURE_TTHW" "status-view.py" || return
  pass_test
}

test_measure_tthw_e2e() {
  start_test "T2: measure-tthw 从空项目量到第一个 active req"

  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 TTHW e2e（T1 静态契约仍执行）"
    return
  fi

  local out err project_dir artifact status total
  out="$(mktemp)"
  err="$(mktemp)"

  if ! bash "$MEASURE_TTHW" --threshold-seconds 60 --keep >"$out" 2>"$err"; then
    _fail "measure-tthw.sh 执行失败"
    echo "--- stderr ---" >&2
    cat "$err" >&2
    echo "--- stdout ---" >&2
    cat "$out" >&2
    rm -f "$out" "$err"
    return
  fi

  status="$(json_value "$out" status)"
  total="$(json_value "$out" total_tthw_seconds)"
  project_dir="$(json_value "$out" project_dir)"
  artifact="$(json_value "$out" artifact)"

  if [ "$status" != "pass" ]; then
    _fail "TTHW status 应为 pass，实际: $status"
    cat "$out" >&2
    rm -rf "$(json_value "$out" run_root 2>/dev/null || true)"
    rm -f "$out" "$err"
    return
  fi
  if ! python3 - "$total" <<'PY'
import sys
raise SystemExit(0 if float(sys.argv[1]) <= 60 else 1)
PY
  then
    _fail "TTHW 超过 60s: $total"
    cat "$out" >&2
    rm -rf "$(json_value "$out" run_root 2>/dev/null || true)"
    rm -f "$out" "$err"
    return
  fi
  if [ ! -f "$artifact" ]; then
    _fail "TTHW artifact 不存在: $artifact"
    cat "$out" >&2
    rm -rf "$(json_value "$out" run_root 2>/dev/null || true)"
    rm -f "$out" "$err"
    return
  fi
  if ! (cd "$project_dir" && python3 .claude/scripts/status-view.py) \
    | grep -q "当前 Req"; then
    _fail "status-view.py 未识别 active req"
    cat "$out" >&2
    rm -rf "$(json_value "$out" run_root 2>/dev/null || true)"
    rm -f "$out" "$err"
    return
  fi

  rm -rf "$(json_value "$out" run_root)"
  rm -f "$out" "$err"
  pass_test
}

test_contract_is_documented
test_measure_tthw_e2e

report_results "tthw-smoke"
