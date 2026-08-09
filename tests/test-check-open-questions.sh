#!/usr/bin/env bash
# Tests for scripts/check-open-questions.py
#
# 验证未决问题闸门 lint 在以下场景的判定：
# - 全已答 → exit 0
# - 有未答 → exit 1 + 列出未答题号 / 行号
# - section 不存在 → exit 0
# - section 显式声明"本次工作无未决问题" → exit 0
# - 同行答案 / 后续行答案两种格式都识别
# - `## 待确认问题` 与 `## 未决问题` 同样受检，只认最后一个当前 section
# - Q 缺 `PM 回答` 标记也会 fail
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

test_pending_questions_heading_is_supported() {
  start_test "## 待确认问题 与 ## 未决问题 使用同一闸门"
  local md
  md=$(_write_md '# X

## 待确认问题

### Q1: 题一

**PM 回答：** 已确认
')
  python3 "$CHECKER" "$md" --require-section >/dev/null
  local rc=$?
  assert_equal "0" "$rc" "pending-question heading should be accepted" || { rm -f "$md"; return; }
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

test_missing_answer_marker_is_unanswered() {
  start_test "Q 缺 PM 回答标记 → exit 1"
  local md
  md=$(_write_md '# X

## 未决问题

### Q1: 没有回答标记

这里仅有问题背景。
')
  local out; out=$(python3 "$CHECKER" "$md" 2>&1)
  local rc=$?
  assert_equal "1" "$rc" "missing PM answer marker should fail" || { rm -f "$md"; return; }
  echo "$out" | grep -q "Q1" || { _fail "should mention Q1"; rm -f "$md"; return; }
  rm -f "$md"
  pass_test
}

test_empty_or_descriptive_section_is_unresolved() {
  start_test "空壳或只有说明的开放问题 section 不能通过硬闸门"
  local content md out rc
  for content in "" "这里稍后整理。"; do
    md=$(_write_md "# X

## 未决问题

$content
")
    out=$(python3 "$CHECKER" "$md" --require-section 2>&1)
    rc=$?
    if [ "$rc" != "1" ] || ! echo "$out" | grep -q "缺少可验证的问题"; then
      _fail "empty/descriptive section should remain unresolved: rc=$rc out=$out"
      rm -f "$md"
      return
    fi
    rm -f "$md"
  done
  pass_test
}

test_placeholder_answers_are_unresolved() {
  start_test "待确认/待定/未知/仍需讨论等占位内容不是有效 PM 回答"
  local md out rc
  md=$(_write_md '# X

## 待确认问题

### Q1: inline placeholder
**PM 回答：** 待确认

### Q2: follow-up placeholder
**PM 回答：**
尚未决定，待 PM 确认。

### Q3: comment placeholder
**PM 回答：** <!-- 待填写 -->

### Q4: token with explanation
**PM 回答：** TODO: 等待业务结论

### Q5: role-qualified placeholder
**PM 回答：** 待 PM 确认

### Q6: deferred placeholder
**PM 回答：** 稍后填写

### Q7:
**PM 回答：** 已确认

### Q8: undecided
**PM 回答：** 待定

### Q9: uncertain
**PM 回答：** 不确定

### Q10: unknown
**PM 回答：** 未知

### Q11: discussion required
**PM 回答：** 仍需讨论

### Q12: cross-functional discussion required
**PM 回答：** 需要产品和法务进一步讨论
')
  out=$(python3 "$CHECKER" "$md" --require-section 2>&1)
  rc=$?
  if [ "$rc" != "1" ]; then
    _fail "placeholder answers should fail: rc=$rc out=$out"
    rm -f "$md"
    return
  fi
  for question in Q1 Q2 Q3 Q4 Q5 Q6 Q7 Q8 Q9 Q10 Q11 Q12; do
    if ! echo "$out" | grep -q "$question"; then
      _fail "placeholder answer should report $question: $out"
      rm -f "$md"
      return
    fi
  done
  rm -f "$md"
  pass_test
}

test_only_latest_open_question_section_is_current() {
  start_test "只检查最后一个开放问题 section，历史未答不回流"
  local md
  md=$(_write_md '# X

## 未决问题

### Q1: 历史问题

**PM 回答：**

## 讨论结论

历史讨论里的问题是否继续？

## 待确认问题

### Q2: 当前问题

**PM 回答：** 已确认
')
  python3 "$CHECKER" "$md" --require-section >/dev/null
  local rc=$?
  assert_equal "0" "$rc" "historical sections should not remain unresolved" || { rm -f "$md"; return; }
  rm -f "$md"
  pass_test
}

test_examples_and_comments_cannot_replace_current_section() {
  start_test "代码示例和 HTML 注释中的假 section 不能覆盖真实未决问题"
  local md out rc
  md=$(_write_md '# X

## 未决问题

### Q1: 真实未决问题

**PM 回答：**

```markdown
## 未决问题
本轮工作无未决问题
```

<!--
## 待确认问题
本轮工作无未决问题
-->
')
  out=$(python3 "$CHECKER" "$md" --require-section 2>&1)
  rc=$?
  if [ "$rc" != "1" ] || ! echo "$out" | grep -q "Q1"; then
    _fail "hidden example section should not bypass the real question: rc=$rc out=$out"
    rm -f "$md"
    return
  fi
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

test_only_independent_affirmative_none_is_accepted() {
  start_test "无未决声明只接受独立、肯定的完整声明"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO_ROOT/scripts/_lib/open_questions.py" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("open_questions_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

cases = [
    ("本轮工作无未决问题。", True),
    ("（本项目无未决问题）", True),
    ("- **本次工作无未决问题。**", True),
    ("并非本轮工作无未决问题。", False),
    ("讨论稿写着“本轮工作无未决问题”。", False),
    ("本轮工作无未决问题，但退款规则仍待确认。", False),
    ("本轮工作无未决问题。后续仍需确认退款规则。", False),
    ("本轮工作无未决问题。\n后续仍需确认退款规则。", False),
]
for text, expected in cases:
    actual = module.explicitly_no_open_questions(text)
    assert actual is expected, (text, actual, expected)
PY
  then
    pass_test
  else
    _fail "explicitly_no_open_questions declaration semantics regressed"
  fi
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
  start_test "skills/design/SKILL.md 以 --require-section 调用开放问题闸门"
  local skill="$REPO_ROOT/skills/design/SKILL.md"
  assert_file_contains "$skill" "check-open-questions.py" || return
  assert_file_contains "$skill" "--require-section" || return
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_all_answered
test_pending_questions_heading_is_supported
test_has_unanswered
test_missing_answer_marker_is_unanswered
test_empty_or_descriptive_section_is_unresolved
test_placeholder_answers_are_unresolved
test_only_latest_open_question_section_is_current
test_examples_and_comments_cannot_replace_current_section
test_no_section
test_explicit_none
test_current_round_explicit_none
test_only_independent_affirmative_none_is_accepted
test_inline_and_follow_up_answer
test_blank_answer_before_next_question
test_missing_file
test_quiet_mode
test_skill_invokes_script

report_results "check-open-questions"
