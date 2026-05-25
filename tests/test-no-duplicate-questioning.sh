#!/usr/bin/env bash
# test-no-duplicate-questioning.sh
#
# 验证 _shared/project-questioning.md 是单一真相源（D-iv M1 vp-5a；review A1 + C-6）：
#   T1: Decision gate 模板（"我会开始写 .planning/PROJECT.md, 进入" prose）只在 _shared 一处
#   T2: 6 节齐不齐检查（check-project-sections.py + all_filled 判定逻辑）只在 _shared 一处
#   T3: 未决问题闸门（check-open-questions.py + --require-section + 暂存文件路径）只在 _shared 一处
#   T4: 5 组话术 6 节问题库表（典型话术 column）只在 _shared 一处
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_FILE="$REPO_ROOT/skills/_shared/project-questioning.md"

# 辅助：在 skills/ 全树 grep 给定 pattern，返回命中文件数（去重）
_count_files_with() {
  local pattern="$1"
  grep -rl "$pattern" "$REPO_ROOT/skills/" 2>/dev/null | sort -u | wc -l | tr -d ' '
}

# -----------------------------------------------------------------
# T1: Decision gate 模板内嵌副本检测
#   gsd 原文 "我会开始写 .planning/PROJECT.md" 是 _shared §6.2 模板里的具体话术
#   其他 SKILL 应该 @读 §6.2 引用，不内嵌副本
# -----------------------------------------------------------------
test_decision_gate_template_single_source() {
  start_test "T1: Decision gate 模板话术只在 _shared/project-questioning.md 一处"
  if [ ! -f "$SHARED_FILE" ]; then
    _fail "_shared/project-questioning.md 不存在 — vp-2 应已创建"
    return
  fi
  local cnt
  cnt=$(_count_files_with "我会开始写 .planning/PROJECT.md")
  if [ "$cnt" -gt 1 ]; then
    _fail "Decision gate 模板话术在 $cnt 个文件出现（应只在 _shared 一处）：$(grep -rl '我会开始写 .planning/PROJECT.md' "$REPO_ROOT/skills/" 2>/dev/null)"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T2: 6 节齐不齐**完整调用代码块**（PROJECT_STATE=$(python3 ... + ALL_FILLED + EMPTY 3 行块）
#   只在 _shared 一处（new-req mini-fill 是 legacy 兜底，允许独立持有；不算重复）
#   关键：检测 init-project / project-solution 不持有该完整代码块副本
# -----------------------------------------------------------------
test_section_check_block_not_in_d_iv_skills() {
  start_test "T2: 6 节齐不齐完整调用代码块不出现在 init-project / project-solution（_shared + new-req legacy 兜底各持一份合法）"
  for skill in init-project project-solution; do
    if grep -q 'PROJECT_STATE=$(python3' "$REPO_ROOT/skills/$skill/SKILL.md" 2>/dev/null; then
      _fail "$skill/SKILL.md 不应持有 PROJECT_STATE=\$(python3 完整代码块副本（应 @读 _shared §7）"
      return
    fi
  done
  # 同时验证 _shared 一定持有（防 _shared 被误删）
  if ! grep -q 'PROJECT_STATE=$(python3' "$SHARED_FILE" 2>/dev/null; then
    _fail "_shared/project-questioning.md 缺 PROJECT_STATE=\$(python3 调用代码块（§7 6 节齐不齐检查）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T3: 未决问题闸门**完整调用代码块**（python3 ... check-open-questions.py ... --require-section）
#   只在 _shared 一处（init-project / project-solution 仅引用路径名是合法的说明性引用，不算副本）
# -----------------------------------------------------------------
test_open_questions_gate_block_only_in_shared() {
  start_test "T3: check-open-questions.py --require-section 完整调用代码块只在 _shared 一处"
  local cnt
  cnt=$(grep -rl 'check-open-questions\.py.*\.project-solution-open-questions\.md.*--require-section\|--require-section.*\.project-solution-open-questions\.md' "$REPO_ROOT/skills/" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  # 单行匹配难捕获多行 bash heredoc，改用更精确的检查：grep _shared 必含完整调用 + init-project / project-solution 不含
  if ! grep -q "check-open-questions.py" "$SHARED_FILE" 2>/dev/null; then
    _fail "_shared/project-questioning.md 缺 check-open-questions.py 调用（§4 未决问题闸门）"
    return
  fi
  for skill in init-project project-solution; do
    if grep -q "check-open-questions\.py.*--require-section" "$REPO_ROOT/skills/$skill/SKILL.md" 2>/dev/null; then
      _fail "$skill/SKILL.md 不应持有 check-open-questions.py --require-section 完整调用（应 @读 _shared §4）"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
# T4: 问题库 6 节典型话术只在 _shared 一处
#   "这个项目要解决什么核心问题？" 是 _shared §3 问题库里的具体话术
# -----------------------------------------------------------------
test_question_library_single_source() {
  start_test "T4: 问题库典型话术只在 _shared/project-questioning.md 一处"
  local cnt
  cnt=$(_count_files_with "这个项目要解决什么核心问题")
  if [ "$cnt" -gt 1 ]; then
    _fail "问题库话术在 $cnt 个文件出现（应只在 _shared 一处）：$(grep -rl '这个项目要解决什么核心问题' "$REPO_ROOT/skills/" 2>/dev/null)"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_decision_gate_template_single_source
test_section_check_block_not_in_d_iv_skills
test_open_questions_gate_block_only_in_shared
test_question_library_single_source

report_results "no-duplicate-questioning"
