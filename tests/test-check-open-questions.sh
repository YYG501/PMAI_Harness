#!/usr/bin/env bash
# Tests for scripts/check-open-questions.py
#
# 验证未决问题闸门 lint 在以下场景的判定：
# - 全已答 → exit 0
# - 有未答 → exit 1 + 列出未答题号 / 行号
# - section 不存在 → exit 0
# - section 显式声明"本次工作无未决问题" → exit 0
# - 同行答案 / 后续行答案两种格式都识别
# - 文件不存在 → exit 2
# - SKILL.md 引用本脚本（防止重构时丢失）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-open-questions.py"

# Helper: 写一份临时 md 文件并返回路径
_write_md() {
  local content="$1"
  local tmp; tmp=$(mktemp)
  printf "%s" "$content" > "$tmp"
  echo "$tmp"
}

# -----------------------------------------------------------------
# Scenario 1: 全部已答
# -----------------------------------------------------------------
test_all_answered() {
  start_test "全部 PM 回答已填 → exit 0"
  local md
  md=$(_write_md '# X

## 未决问题

### Q1: 题一

题干

**PM 回答：** A

### Q2: 题二

题干

**PM 回答：**

A 选项
')

  python3 "$CHECKER" "$md" >/dev/null
  local rc=$?
  assert_equal "0" "$rc" "all answered should exit 0" || { rm -f "$md"; return; }

  rm -f "$md"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 2: 有未答
# -----------------------------------------------------------------
test_has_unanswered() {
  start_test "有未答 PM 回答 → exit 1 + 输出未答题号"
  local md
  md=$(_write_md '# X

## 未决问题

### Q1: 已答题

**PM 回答：** OK

### Q2: 未答题

**PM 回答：**

### Q3: 也未答

**PM 回答：**
')

  local out; out=$(python3 "$CHECKER" "$md" 2>&1)
  local rc=$?
  assert_equal "1" "$rc" "has unanswered should exit 1" || { rm -f "$md"; return; }

  echo "$out" | grep -q "Q2" || { _fail "should mention Q2"; rm -f "$md"; return; }
  echo "$out" | grep -q "Q3" || { _fail "should mention Q3"; rm -f "$md"; return; }
  echo "$out" | grep -Eq '^[[:space:]]*-[[:space:]]+Q1（' && { _fail "should NOT mention Q1 (already answered)"; rm -f "$md"; return; }

  rm -f "$md"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 3: section 不存在
# -----------------------------------------------------------------
test_no_section() {
  start_test "无 ## 未决问题 section → exit 0（不触发闸门）"
  local md
  md=$(_write_md '# X

## 章节一

正文，没有未决问题 section
')
  python3 "$CHECKER" "$md" >/dev/null
  local rc=$?
  assert_equal "0" "$rc" "no section should exit 0" || { rm -f "$md"; return; }

  rm -f "$md"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 4: section 显式声明无未决问题
# -----------------------------------------------------------------
test_explicit_none() {
  start_test "section 写「本次工作无未决问题」→ exit 0"
  local md
  md=$(_write_md '# X

## 未决问题

（本次工作无未决问题）
')
  python3 "$CHECKER" "$md" >/dev/null
  local rc=$?
  assert_equal "0" "$rc" "explicit none should exit 0" || { rm -f "$md"; return; }

  rm -f "$md"
  pass_test
}

test_current_round_explicit_none() {
  start_test "section 写「本轮工作无未决问题」→ exit 0"
  local md
  md=$(_write_md '# X

## 未决问题

本轮工作无未决问题。
')
  python3 "$CHECKER" "$md" >/dev/null
  local rc=$?
  assert_equal "0" "$rc" "current-round explicit none should exit 0" || { rm -f "$md"; return; }

  rm -f "$md"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 5: 同行答案 / 后续行答案两种格式
# -----------------------------------------------------------------
test_inline_and_follow_up_answer() {
  start_test "同行答案 + 后续行答案 两种格式都识别为已答"
  local md
  md=$(_write_md '# X

## 未决问题

### Q1: 同行答案

**PM 回答：** 直接同行

### Q2: 后续行答案

**PM 回答：**

下一行的答案。
')
  python3 "$CHECKER" "$md" >/dev/null
  local rc=$?
  assert_equal "0" "$rc" "both inline and follow-up answer accepted" || { rm -f "$md"; return; }

  rm -f "$md"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 6: 答案后接下一题，被正确判为未答
# -----------------------------------------------------------------
test_blank_answer_before_next_question() {
  start_test "PM 回答后紧接下一个 ### 题目（中间无内容）→ 判为未答"
  local md
  md=$(_write_md '# X

## 未决问题

### Q1: 第一题

**PM 回答：**
### Q2: 第二题

**PM 回答：** 答了
')
  python3 "$CHECKER" "$md" >/dev/null
  local rc=$?
  assert_equal "1" "$rc" "should detect blank Q1" || { rm -f "$md"; return; }

  rm -f "$md"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 7: 文件不存在
# -----------------------------------------------------------------
test_missing_file() {
  start_test "文件不存在 → exit 2"
  python3 "$CHECKER" /tmp/does-not-exist-$$ >/dev/null 2>&1
  local rc=$?
  assert_equal "2" "$rc" "missing file should exit 2" || return
  pass_test
}

# -----------------------------------------------------------------
# Scenario 8: --quiet 不打印
# -----------------------------------------------------------------
test_quiet_mode() {
  start_test "--quiet 不输出未答清单（exit code 仍 1）"
  local md
  md=$(_write_md '# X

## 未决问题

### Q1: foo

**PM 回答：**
')
  local out; out=$(python3 "$CHECKER" "$md" --quiet 2>&1)
  local rc=$?
  assert_equal "1" "$rc" "quiet still exits 1 on unanswered" || { rm -f "$md"; return; }
  if [ -n "$out" ]; then
    _fail "--quiet should produce no output, got: $out"
    rm -f "$md"; return
  fi

  rm -f "$md"
  pass_test
}

# -----------------------------------------------------------------
# Scenario 9: active design skill 仍然引用脚本
# -----------------------------------------------------------------
test_skill_invokes_script() {
  start_test "skills/design/SKILL.md 引用 check-open-questions.py"
  local skill="$REPO_ROOT/skills/design/SKILL.md"
  assert_file_contains "$skill" "check-open-questions.py" || return
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_all_answered
test_has_unanswered
test_no_section
test_explicit_none
test_current_round_explicit_none
test_inline_and_follow_up_answer
test_blank_answer_before_next_question
test_missing_file
test_quiet_mode
test_skill_invokes_script

report_results "check-open-questions"
