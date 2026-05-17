#!/usr/bin/env bash
# Tests for scripts/check-lark-cli-direct-usage.py：
# - 干净仓 exit 0
# - 故意违规文件 exit 非 0
# - allowlist 文件不报
# - 行级豁免注释生效
# - 文档教学段（lark-cli docs/api/auth）不报
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINT="$FRAMEWORK_ROOT/scripts/check-lark-cli-direct-usage.py"

test_clean_repo_passes() {
  start_test "lint 在当前主仓干净"
  if python3 "$LINT" "$FRAMEWORK_ROOT" >/tmp/lint_clean.$$ 2>&1; then
    pass_test
  else
    _fail "expected lint pass on main repo"
    cat /tmp/lint_clean.$$ >&2
  fi
  rm -f /tmp/lint_clean.$$
}

test_violating_file_caught() {
  start_test "故意违规文件被抓"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scripts"
  cat > "$tmp/scripts/bad.py" <<'PY'
import subprocess
res = subprocess.run(["lark-cli", "docs", "+create"])
PY
  if python3 "$LINT" "$tmp" >/tmp/lint_bad.$$ 2>&1; then
    _fail "expected lint to fail; output: $(cat /tmp/lint_bad.$$)"
  elif grep -q "scripts/bad.py" /tmp/lint_bad.$$; then
    pass_test
  else
    _fail "expected scripts/bad.py in output"
    cat /tmp/lint_bad.$$ >&2
  fi
  rm -rf "$tmp" /tmp/lint_bad.$$
}

test_allowlist_file_ignored() {
  start_test "allowlist 文件不报"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scripts/_lib"
  cat > "$tmp/scripts/_lib/lark_adapter.py" <<'PY'
import subprocess
subprocess.run(["lark-cli", "--version"])  # this is the adapter itself
PY
  if python3 "$LINT" "$tmp" >/tmp/lint_allow.$$ 2>&1; then
    pass_test
  else
    _fail "expected lint pass; output: $(cat /tmp/lint_allow.$$)"
  fi
  rm -rf "$tmp" /tmp/lint_allow.$$
}

test_doc_teaching_line_ignored() {
  start_test "文档教学段 lark-cli docs/api/auth 不报"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/skills/foo"
  cat > "$tmp/skills/foo/SKILL.md" <<'MD'
# Foo skill

PM 在命令行可以跑：

```
lark-cli auth login --scope docx:document:write_only
lark-cli docs +create --title "标题" --markdown @./foo.md
```

详见 lark-shared skill。
MD
  if python3 "$LINT" "$tmp" >/tmp/lint_teach.$$ 2>&1; then
    pass_test
  else
    _fail "expected lint pass; output: $(cat /tmp/lint_teach.$$)"
  fi
  rm -rf "$tmp" /tmp/lint_teach.$$
}

test_doc_teaching_with_quoted_literal_still_caught() {
  start_test "文档段含 \"lark-cli\" 字符串字面量仍报"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/skills/foo"
  cat > "$tmp/skills/foo/SKILL.md" <<'MD'
# Foo

代码示例：
    subprocess.run(["lark-cli", "docs", "+create"])
MD
  if python3 "$LINT" "$tmp" >/tmp/lint_quoted.$$ 2>&1; then
    _fail "expected lint to fail"
  else
    pass_test
  fi
  rm -rf "$tmp" /tmp/lint_quoted.$$
}

test_lint_skip_marker_honored() {
  start_test "行尾 # lint-skip-lark-cli 注释豁免"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/scripts"
  cat > "$tmp/scripts/legacy.py" <<'PY'
import subprocess
subprocess.run(["lark-cli", "--version"])  # lint-skip-lark-cli: legacy bootstrap
PY
  if python3 "$LINT" "$tmp" >/tmp/lint_skip.$$ 2>&1; then
    pass_test
  else
    _fail "expected lint pass due to marker; output: $(cat /tmp/lint_skip.$$)"
  fi
  rm -rf "$tmp" /tmp/lint_skip.$$
}

test_clean_repo_passes
test_violating_file_caught
test_allowlist_file_ignored
test_doc_teaching_line_ignored
test_doc_teaching_with_quoted_literal_still_caught
test_lint_skip_marker_honored

report_results "lark-cli-lint"
