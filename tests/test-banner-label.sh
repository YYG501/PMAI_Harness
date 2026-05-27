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
# T6: 7 个核心 SKILL 真的在 body 里调用 banner（不只是顶部 prose 指针）
# -----------------------------------------------------------------
# 验证方式：每个 SKILL.md 必须含至少 2 次 banner 引用 ——
#   1 次顶部 PM 视图 prose 指针（T1 已查），
#   1 次 body 真实调用（status-view.py --banner-only 调用 OR 字面值 echo "━━━ PMAI ► ..."）
# 这是 D-iv v0.3 patch 修 "banner 设计骗局" BLOCKER 的硬约束。
test_all_core_skills_invoke_banner_in_body() {
  start_test "T6: 7 核心 SKILL body 真调用 banner（非仅顶部指针）"
  local missing=()
  for skill in "${CORE_SKILLS[@]}"; do
    local file="$REPO_ROOT/skills/$skill/SKILL.md"
    # 计 banner 引用总数（status-view 调用 + 字面值 banner echo 都算）
    local cnt
    cnt=$(grep -cE "status-view\.py.*--banner-only|━━━ PMAI ► [A-Z-]+ ▸" "$file" 2>/dev/null || echo 0)
    if [ "$cnt" -lt 2 ]; then
      missing+=("$skill(只有 $cnt 处，需 ≥2)")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    _fail "以下 SKILL body 未真调 banner：${missing[*]}"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T7: 7 个核心 SKILL 退出处含 Next Up 关键词
# -----------------------------------------------------------------
test_all_core_skills_have_next_up() {
  start_test "T7: 7 核心 SKILL 退出处含 ▶ Next Up 关键词"
  local missing=()
  for skill in "${CORE_SKILLS[@]}"; do
    if ! grep -qE "▶ Next Up" "$REPO_ROOT/skills/$skill/SKILL.md" 2>/dev/null; then
      missing+=("$skill")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    _fail "以下 SKILL 缺 ▶ Next Up 块：${missing[*]}"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T8: task-confirm SKILL.md 不再有"执行前确认闸门"自相矛盾
# -----------------------------------------------------------------
test_task_confirm_no_contradiction() {
  start_test "T8: task-confirm 顶部指针不再写「执行前确认闸门 label」（与 delta-3 §2.3 一致）"
  # 顶部指针段（行 1-15 内）若含"执行前确认闸门"就是 D-iv 自相矛盾未修
  if sed -n '1,15p' "$REPO_ROOT/skills/task-confirm/SKILL.md" | grep -q "执行前确认闸门"; then
    _fail "task-confirm 顶部仍写「执行前确认闸门 label」，与 body 行 23-25 「不再设确认闸门」矛盾"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

# -----------------------------------------------------------------
# T9: banner-rules.md §3 含 §3.0 适用范围（仅 AskUserQuestion picker）
# -----------------------------------------------------------------
# D-iv v0.3 patch 加：§3 不再无差别管所有闸门，只管 GUI picker 形式；
# chat 自由对话续跑闸门走常规形态。验证适用范围段存在 + 关键判定字眼。
test_banner_rules_scope_disclaimer() {
  start_test "T9: banner-rules §3 含 §3.0 适用范围（AskUserQuestion + picker 形态）"
  if ! grep -q "§3.0 适用范围" "$BANNER_RULES"; then
    _fail "banner-rules.md 缺 §3.0 适用范围段"
    return
  fi
  section=$(awk '/### §3\.0/,/### §3\.1/' "$BANNER_RULES")
  if ! echo "${section}" | grep -q "AskUserQuestion"; then
    _fail "banner-rules.md §3.0 未点明 AskUserQuestion 形态"
    return
  fi
  if ! echo "${section}" | grep -q "picker"; then
    _fail "banner-rules.md §3.0 未提及 picker 形态"
    return
  fi
  if ! grep -q "反问澄清\|prose 反问\|prose 输出" "$BANNER_RULES"; then
    _fail "banner-rules.md §3.0 未说明 prose 输出 / 反问澄清不受 §3 约束"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T10: req-stage-gate office-hours slug fail-loud（D-iv v0.3 patch）
# -----------------------------------------------------------------
# 旧代码 SLUG="unknown" silent fallback 让 PM 误以为"没探测到产物"；新代码必须 fail-loud
test_office_hours_slug_fail_loud() {
  start_test "T10: req-stage-gate office-hours slug 解析 fail-loud（不 silent fallback unknown）"
  local f="$REPO_ROOT/skills/req-stage-gate/SKILL.md"
  # 旧 silent fallback 字眼不该再有
  if grep -q 'SLUG="unknown"' "$f"; then
    _fail "req-stage-gate 仍含 SLUG=\"unknown\" silent fallback（应改 fail-loud）"
    return
  fi
  # 新增 SLUG_ERR 错误捕获变量应在
  if ! grep -q "SLUG_ERR" "$f"; then
    _fail "req-stage-gate 缺 SLUG_ERR 错误捕获（fail-loud 关键变量）"
    return
  fi
  # 三态分流应有显式 "无法定位" 文案
  if ! grep -q "无法定位 gstack 项目目录" "$f"; then
    _fail "req-stage-gate 缺「无法定位 gstack 项目目录」分流文案"
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
test_all_core_skills_invoke_banner_in_body
test_all_core_skills_have_next_up
test_task_confirm_no_contradiction
test_banner_rules_scope_disclaimer
test_office_hours_slug_fail_loud

report_results "banner-label"
