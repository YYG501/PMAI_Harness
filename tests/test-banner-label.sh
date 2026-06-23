#!/usr/bin/env bash
# test-banner-label.sh
#
# 验证 M2 banner + Decision gate label 规范在核心 SKILL 落地（D-iv M1 vp-8）：
#   T1: 核心 SKILL.md 顶部都引用 banner-rules.md
#   T2: banner-rules.md 含 §3 Decision gate label 3 硬规则
#   T3: banner-rules.md 含「禁用模糊词」清单（OK / Proceed / Continue）
#   T4: _lib/state.py 暴露 get_current_stage_banner（vp-7 helper）
#   T5: status-view.py --banner-only 模式存在
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BANNER_RULES="$REPO_ROOT/skills/_shared/pm-view/banner-rules.md"

# 核心 SKILL（用户面 skill）
CORE_SKILLS=(
  init-project
  design
  build
  close
  cancel
)

# -----------------------------------------------------------------
# T1: 核心 SKILL 都引用 banner-rules.md
# -----------------------------------------------------------------
test_all_core_skills_reference_banner_rules() {
  start_test "T1: 核心 SKILL.md 顶部都引用 banner-rules.md"
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
# T5b: --banner-only 在有 active work 时真渲染 banner，不抛异常
# 回归 codex 审出的 P1：render_banner_only 读 work_view["dir"]，但状态层
# 返回的 key 是 work_dir → KeyError，且该行在 try 外不被兜底 → 所有 skill 横幅崩。
# T5 只静态 grep 参数存在，构造不出 active work 跑不到这条路（覆盖缺口）。
# -----------------------------------------------------------------
test_banner_only_renders_active_work() {
  start_test "T5b: --banner-only 有 active work 时真渲染（P1 KeyError 回归）"
  fixture_setup
  fixture_create_work "work-001" "test" 2 >/dev/null

  local out rc
  out=$(cd "$FIXTURE_DIR" && python3 "$REPO_ROOT/scripts/status-view.py" --banner-only --skill design 2>&1)
  rc=$?

  if [ "$rc" != "0" ]; then
    _fail "--banner-only 非 0 退出 (rc=$rc)。输出：$out"; fixture_teardown; return
  fi
  if echo "$out" | grep -qE "渲染失败|KeyError|Traceback"; then
    _fail "--banner-only 渲染异常。输出：$out"; fixture_teardown; return
  fi
  if ! echo "$out" | grep -q "PMAI"; then
    _fail "--banner-only 未输出 PMAI 横幅。输出：$out"; fixture_teardown; return
  fi
  fixture_teardown
  pass_test
}

# -----------------------------------------------------------------
# T6: 核心 SKILL 真的在 body 里调用 banner
# -----------------------------------------------------------------
# 验证方式：每个 SKILL.md 至少有 1 次真实调用
# （status-view.py --banner-only 调用 OR 字面值 echo "━━━ PMAI ► ..."）。
test_all_core_skills_invoke_banner_in_body() {
  start_test "T6: 核心 SKILL body 真调用 banner"
  local missing=()
  for skill in "${CORE_SKILLS[@]}"; do
    local file="$REPO_ROOT/skills/$skill/SKILL.md"
    # 计 banner 引用总数（status-view 调用 + 字面值 banner echo 都算）
    local cnt
    cnt=$(grep -cE "status-view\.py.*--banner-only|━━━ PMAI ► [A-Z-]+ ▸" "$file" 2>/dev/null || true)
    cnt="${cnt:-0}"
    if [ "$cnt" -lt 1 ]; then
      missing+=("$skill")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    _fail "以下 SKILL body 未真调 banner：${missing[*]}"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T7: 核心 SKILL 退出处含 Next Up 关键词
# -----------------------------------------------------------------
test_all_core_skills_have_next_up() {
  start_test "T7: 核心 SKILL 退出处含 ▶ Next Up 关键词"
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

test_all_core_skills_reference_banner_rules
test_banner_rules_has_label_3_rules
test_banner_rules_lists_forbidden_words
test_state_lib_exposes_banner_helper
test_status_view_has_banner_only
test_banner_only_renders_active_work
test_all_core_skills_invoke_banner_in_body
test_all_core_skills_have_next_up
test_banner_rules_scope_disclaimer

report_results "banner-label"
