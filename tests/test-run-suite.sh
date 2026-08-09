#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
RUNNER="$SCRIPT_DIR/run-suite.py"
EVAL_SUMMARY="$SCRIPT_DIR/parse-skill-eval-summary.py"

run_fixture() {
  local body="$1"
  local timeout="${2:-2}"
  FIXTURE=$(mktemp "${TMPDIR:-/tmp}/pmai-run-suite.XXXXXX")
  RESULT=$(mktemp "${TMPDIR:-/tmp}/pmai-run-suite-result.XXXXXX")
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$FIXTURE"
  chmod +x "$FIXTURE"
  python3 "$RUNNER" --timeout "$timeout" --result-file "$RESULT" -- bash "$FIXTURE" \
    >/tmp/run-suite.$$ 2>/tmp/run-suite.err.$$
}

cleanup_fixture() {
  rm -f "${FIXTURE:-}" "${RESULT:-}" /tmp/run-suite.$$ /tmp/run-suite.err.$$
}

test_accepts_valid_summary() {
  start_test "run-suite: accepts one valid Passed/Failed summary"
  if run_fixture $'echo "Passed: 2"\necho "Failed: 0"'; then
    if python3 - "$RESULT" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["status"] == "passed"
assert result["passed"] == 2
assert result["failed"] == 0
PY
    then
      pass_test
    else
      _fail "valid summary result mismatch"
    fi
  else
    _fail "valid summary should pass"
    cat /tmp/run-suite.err.$$ >&2
  fi
  cleanup_fixture
}

test_rejects_missing_summary() {
  start_test "run-suite: missing summary fails closed"
  if run_fixture 'echo done'; then
    _fail "missing summary should fail"
  elif grep -q "测试摘要格式异常" /tmp/run-suite.err.$$; then
    pass_test
  else
    _fail "missing summary guidance mismatch"
  fi
  cleanup_fixture
}

test_rejects_duplicate_summary() {
  start_test "run-suite: duplicate summaries fail closed"
  if run_fixture $'echo "Passed: 1"\necho "Failed: 0"\necho "Passed: 1"\necho "Failed: 0"'; then
    _fail "duplicate summaries should fail"
  elif grep -q "实际 2 组" /tmp/run-suite.err.$$; then
    pass_test
  else
    _fail "duplicate summary guidance mismatch"
  fi
  cleanup_fixture
}

test_rejects_zero_cases() {
  start_test "run-suite: zero-case summary fails closed"
  if run_fixture $'echo "Passed: 0"\necho "Failed: 0"'; then
    _fail "zero-case summary should fail"
  elif grep -q "不能同时为 0" /tmp/run-suite.err.$$; then
    pass_test
  else
    _fail "zero-case guidance mismatch"
  fi
  cleanup_fixture
}

test_rejects_inconsistent_exit_code() {
  start_test "run-suite: reported failure cannot exit zero"
  if run_fixture $'echo "Passed: 1"\necho "Failed: 1"'; then
    _fail "inconsistent summary should fail"
  elif grep -q "suite 退出码为 0" /tmp/run-suite.err.$$; then
    pass_test
  else
    _fail "inconsistent exit guidance mismatch"
  fi
  cleanup_fixture
}

test_skill_eval_summary_rejects_fake_green() {
  start_test "run-all: skill eval reported failures cannot exit zero"
  if printf '%s\n' 'SUMMARY passed=5 failed=1 skipped=0 judge_skipped=0' \
    | python3 "$EVAL_SUMMARY" --exit-code 0 >/tmp/run-suite.$$ 2>/tmp/run-suite.err.$$; then
    _fail "skill eval fake green should fail"
  elif grep -q "SUMMARY 与退出码矛盾" /tmp/run-suite.err.$$; then
    pass_test
  else
    _fail "skill eval fake-green guidance mismatch"
  fi
  cleanup_fixture
}

test_skill_eval_summary_accepts_reported_failure() {
  start_test "run-all: skill eval failure summary matches non-zero exit"
  if [ "$(printf '%s\n' 'SUMMARY passed=5 failed=1 skipped=2 judge_skipped=0' \
    | python3 "$EVAL_SUMMARY" --exit-code 1)" = "5 1 2 0" ]; then
    pass_test
  else
    _fail "consistent skill eval failure should parse"
  fi
}

test_times_out_process_group() {
  start_test "run-suite: suite timeout is explicit"
  if run_fixture $'sleep 2\necho "Passed: 1"\necho "Failed: 0"' 0.1; then
    _fail "timed out suite should fail"
  elif grep -q "超过单套超时 0.1s" /tmp/run-suite.err.$$ && \
       python3 - "$RESULT" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
assert result["status"] == "timeout"
assert result["failed"] == 1
PY
  then
    pass_test
  else
    _fail "timeout result mismatch"
  fi
  cleanup_fixture
}

test_accepts_valid_summary
test_rejects_missing_summary
test_rejects_duplicate_summary
test_rejects_zero_cases
test_rejects_inconsistent_exit_code
test_skill_eval_summary_rejects_fake_green
test_skill_eval_summary_accepts_reported_failure
test_times_out_process_group
report_results "run-suite"
