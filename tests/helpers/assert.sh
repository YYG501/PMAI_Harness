# shellcheck shell=bash
# Assertion helpers for test suite

PASS_COUNT=0
FAIL_COUNT=0
FAILURES=()

_current_test=""

write_equivalent_product_baseline() {
  local repo_root="$1"
  mkdir -p "$repo_root/docs" "$repo_root/.pm-workflow"
  cat > "$repo_root/docs/existing-product-baseline.md" <<'EOF'
# Existing Product Baseline

接入 PMAI 前已经确认的产品立项与范围依据。
EOF
  cat > "$repo_root/PRODUCT.md" <<'EOF'
# Fixture Product

## 当前 Product Proposal

接入前已有等价产品基线。

- 主要依据：`docs/existing-product-baseline.md`
- PM 确认日期：2025-01-01

## 产品定位

帮助业务负责人基于可信信息完成关键判断。

## 核心问题与价值

减少人工查找遗漏，让负责人更快作出可验证的业务行动。

## 用户画像

| 角色 | 描述 | 关键诉求 |
|---|---|---|
| 业务负责人 | 对任务结果负责 | 获得完整依据并完成判断 |

## 产品边界

产品提供信息和建议，最终业务决定由负责人确认。

## MVP Case

负责人收到任务后核对依据、确认建议并提交结果。
EOF
  cat > "$repo_root/PRODUCT-STATE.md" <<'EOF'
# Fixture Product State

## 当前功能 / 能力

| 功能 / 能力 | 状态 | 备注 |
|---|---|---|
| 核心任务闭环 | 已存在 | 测试等价产品基线 |
EOF
  python3 - "$repo_root" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
relative = "docs/existing-product-baseline.md"
payload = {
    "schema_version": 1,
    "files": [
        {
            "path": relative,
            "sha256": hashlib.sha256((root / relative).read_bytes()).hexdigest(),
        }
    ],
}
(root / ".pm-workflow/intake-manifest.json").write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

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
