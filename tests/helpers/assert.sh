# shellcheck shell=bash
# Assertion helpers for test suite

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

_current_test=""

start_test() {
  _current_test="$1"
  echo "  RUN  $_current_test"
}

# Assert command succeeds (exit 0)
assert_success() {
  local desc="$1"
  shift
  if "$@" >/tmp/assert_out.$$ 2>&1; then
    return 0
  else
    _fail "$desc: expected success, got exit $?"
    echo "--- stdout/stderr ---" >&2
    cat /tmp/assert_out.$$ >&2
    return 1
  fi
}

# Assert command fails (exit non-zero)
assert_fail() {
  local desc="$1"
  shift
  if "$@" >/tmp/assert_out.$$ 2>&1; then
    _fail "$desc: expected failure, but succeeded"
    echo "--- stdout/stderr ---" >&2
    cat /tmp/assert_out.$$ >&2
    return 1
  else
    return 0
  fi
}

# Assert command exits with specific code
assert_exit_code() {
  local expected="$1"
  local desc="$2"
  shift 2
  "$@" >/tmp/assert_out.$$ 2>&1
  local actual=$?
  if [ "$actual" = "$expected" ]; then
    return 0
  else
    _fail "$desc: expected exit $expected, got $actual"
    cat /tmp/assert_out.$$ >&2
    return 1
  fi
}

# Assert file exists
assert_file_exists() {
  local path="$1"
  local desc="${2:-file exists: $path}"
  if [ -f "$path" ]; then
    return 0
  else
    _fail "$desc: file not found"
    return 1
  fi
}

# Assert file does NOT exist
assert_file_missing() {
  local path="$1"
  local desc="${2:-file missing: $path}"
  if [ ! -e "$path" ]; then
    return 0
  else
    _fail "$desc: file should not exist but does"
    return 1
  fi
}

# Assert file contents match pattern (grep)
assert_file_contains() {
  local path="$1"
  local pattern="$2"
  local desc="${3:-file $path contains $pattern}"
  if grep -q -- "$pattern" "$path" 2>/dev/null; then
    return 0
  else
    _fail "$desc: pattern not found"
    echo "--- file contents ---" >&2
    cat "$path" >&2 2>/dev/null || echo "(file missing)" >&2
    return 1
  fi
}

# Assert two strings are equal
assert_equal() {
  local expected="$1"
  local actual="$2"
  local desc="${3:-values equal}"
  if [ "$expected" = "$actual" ]; then
    return 0
  else
    _fail "$desc: expected '$expected', got '$actual'"
    return 1
  fi
}

# Assert stderr contains pattern
assert_stderr_contains() {
  local pattern="$1"
  local desc="$2"
  shift 2
  "$@" >/tmp/assert_stdout.$$ 2>/tmp/assert_stderr.$$
  if grep -q -- "$pattern" /tmp/assert_stderr.$$; then
    return 0
  else
    _fail "$desc: stderr missing pattern '$pattern'"
    echo "--- stderr ---" >&2
    cat /tmp/assert_stderr.$$ >&2
    return 1
  fi
}

# Pass/fail helpers
pass_test() {
  local name="${1:-$_current_test}"
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "  ✅ $name"
}

_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILURES+=("$_current_test: $*")
  echo "  ❌ $_current_test: $*" >&2
}

report_results() {
  local suite="$1"
  echo ""
  echo "═════════════════════════════════════════"
  echo "  Suite: $suite"
  echo "  Passed: $PASS_COUNT"
  echo "  Failed: $FAIL_COUNT"
  echo "═════════════════════════════════════════"
  if [ "$FAIL_COUNT" -gt 0 ]; then
    echo ""
    echo "Failures:"
    for f in "${FAILURES[@]}"; do
      echo "  - $f"
    done
    return 1
  fi
  return 0
}
