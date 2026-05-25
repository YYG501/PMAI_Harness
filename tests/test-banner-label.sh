#!/usr/bin/env bash
# test-banner-label.sh
#
# 验证 M2 banner + Decision gate label 规范在 7 个核心 SKILL 落地（D-iv M1 vp-8）：
#   T1: 7 个核心 SKILL.md 顶部都引用 banner-rules.md
#   T2: banner-rules.md 含 §3 Decision gate label 3 硬规则
#   T3: banner-rules.md 含「禁用模糊词」清单（OK / Proceed / Continue）
#   T4: _lib/state.py 暴露 get_current_stage_banner（vp-7 helper）
#   T5: status-view.py --banner-only 模式存在
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BANNER_RULES="$REPO_ROOT/skills/_shared/pm-view/banner-rules.md"

# 7 个核心 SKILL（用户面 skill）
CORE_SKILLS=(
  init-project
  new-req
  req-stage-gate
  task-confirm
  task-execute
  close-task
  close-req
)

# -----------------------------------------------------------------
# T1: 7 个核心 SKILL 都引用 banner-rules.md
# -----------------------------------------------------------------
test_all_core_skills_reference_banner_rules() {
  start_test "T1: 7 个核心 SKILL.md 顶部都引用 banner-rules.md"
  local missing=()
  for skill in "${CORE_SKILLS[@]}"; do
    if ! grep -q "banner-rules.md" "$REPO_ROOT/skills/$skill/SKILL.md" 2>/dev/null; then
      missing+=("$skill")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    _fail "以下 SKILL 缺 banner-rules.md 引用：${missing[*]}"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T2: banner-rules.md 含 §3 Decision gate label 3 硬规则
# -----------------------------------------------------------------
test_banner_rules_has_label_3_rules() {
  start_test "T2: banner-rules.md 含 §3 Decision gate label 3 硬规则"
  if [ ! -f "$BANNER_RULES" ]; then
    _fail "banner-rules.md 不存在"
    return
  fi
  for rule in "label = 动作描述" "description = 一句话解释" "留守选项有 Loop 回路"; do
    if ! grep -q "$rule" "$BANNER_RULES"; then
      _fail "banner-rules.md 缺规则：$rule"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
# T3: banner-rules.md 含禁用模糊词清单（OK / Proceed / Continue）
# -----------------------------------------------------------------
test_banner_rules_lists_forbidden_words() {
  start_test "T3: banner-rules.md 列禁用模糊词（OK / Proceed / Continue）"
  for word in "OK" "Proceed" "Continue"; do
    if ! grep -q "\"$word\"" "$BANNER_RULES"; then
      _fail "banner-rules.md 缺禁用模糊词 \"$word\""
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
# T4: _lib/state.py 暴露 get_current_stage_banner
# -----------------------------------------------------------------
test_state_lib_exposes_banner_helper() {
  start_test "T4: scripts/_lib/state.py 暴露 get_current_stage_banner 函数"
  if ! grep -q "^def get_current_stage_banner" "$REPO_ROOT/scripts/_lib/state.py"; then
    _fail "scripts/_lib/state.py 缺 def get_current_stage_banner"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T5: status-view.py --banner-only 模式存在
# -----------------------------------------------------------------
test_status_view_has_banner_only() {
  start_test "T5: scripts/status-view.py 含 --banner-only 模式"
  if ! grep -q "\\-\\-banner-only" "$REPO_ROOT/scripts/status-view.py"; then
    _fail "scripts/status-view.py 缺 --banner-only argparse 参数"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_all_core_skills_reference_banner_rules
test_banner_rules_has_label_3_rules
test_banner_rules_lists_forbidden_words
test_state_lib_exposes_banner_helper
test_status_view_has_banner_only

report_results "banner-label"
