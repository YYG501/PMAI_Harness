#!/usr/bin/env bash
# req 级「本轮实现深度变更」段（4.5d.3）契约测试
#
# 验证：
# 1. solution.md.tmpl 含 ## 🔧 本轮实现深度变更 section + 默认填「无变更」
# 2. req-solution SKILL 步骤 3 章节顺序含此段 + 写作约束（默认无变更 / 何时填 / 自由文本）
# 3. close-req SKILL 含步骤 2c：检查变更段 + 提示 PM 同步项目级
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOLUTION_TMPL="$REPO_ROOT/templates/solution.md.tmpl"
REQ_SOLUTION_SKILL="$REPO_ROOT/skills/req-solution/SKILL.md"
CLOSE_REQ_SKILL="$REPO_ROOT/skills/close-req/SKILL.md"

test_solution_tmpl_has_depth_change_section() {
  start_test "solution.md.tmpl 含「## 🔧 本轮实现深度变更」section"
  if ! grep -q '^## 🔧 本轮实现深度变更' "$SOLUTION_TMPL"; then
    _fail "solution.md.tmpl 缺「## 🔧 本轮实现深度变更」section"
    return
  fi
  pass_test
}

test_solution_tmpl_default_is_no_change() {
  start_test "solution.md.tmpl 默认填「无变更」"
  # 提取 ## 🔧 本轮实现深度变更 section 直到下一个 ##
  local section
  section=$(awk '/^## 🔧 本轮实现深度变更/{flag=1; next} /^## /{flag=0} flag' "$SOLUTION_TMPL")
  if ! echo "$section" | grep -q "^无变更$"; then
    _fail "solution.md.tmpl 该 section 默认应填「无变更」（独立行）"
    echo "section content:" >&2
    echo "$section" >&2
    return
  fi
  pass_test
}

test_solution_tmpl_section_explains_when_to_fill() {
  start_test "solution.md.tmpl 该 section 注释含「仅在本 req 要改造代码架构时」+ close-req 同步说明"
  if ! grep -q "改造.*代码架构\|改造.*项目代码架构" "$SOLUTION_TMPL"; then
    _fail "section 注释应说明何时填（改造代码架构时）"
    return
  fi
  if ! grep -q "close-req.*同步\|同步.*项目级" "$SOLUTION_TMPL"; then
    _fail "section 注释应说明 close-req 会提示同步项目级"
    return
  fi
  pass_test
}

test_req_solution_skill_lists_section_in_order() {
  start_test "req-solution SKILL 步骤 3 章节顺序含「11. 🔧 本轮实现深度变更」"
  if ! grep -q "本轮实现深度变更" "$REQ_SOLUTION_SKILL"; then
    _fail "req-solution SKILL 缺「本轮实现深度变更」引用"
    return
  fi
  # 11 在 12 历史档案 之前
  local line11 line12
  line11=$(grep -n "11\..*本轮实现深度变更" "$REQ_SOLUTION_SKILL" | head -1 | cut -d: -f1)
  line12=$(grep -n "12\..*历史档案" "$REQ_SOLUTION_SKILL" | head -1 | cut -d: -f1)
  if [ -z "$line11" ] || [ -z "$line12" ]; then
    _fail "req-solution SKILL 章节列表缺 11 或 12"
    return
  fi
  if (( line11 >= line12 )); then
    _fail "11. 本轮实现深度变更 应在 12. 历史档案 之前"
    return
  fi
  pass_test
}

test_req_solution_skill_when_to_fill_guidance() {
  start_test "req-solution SKILL 含「何时填」指引（默认无变更 / 自由文本 / close-req 同步）"
  if ! grep -q "99% 的 req 都填「无变更」\|99%.*无变更" "$REQ_SOLUTION_SKILL"; then
    _fail "req-solution SKILL 应明确「99% req 填无变更」（避免 PM 误把每个 req 都填）"
    return
  fi
  if ! grep -q "自由文本" "$REQ_SOLUTION_SKILL"; then
    _fail "req-solution SKILL 应说明本段是自由文本（不是字段表）"
    return
  fi
  pass_test
}

test_close_req_skill_has_step_2c() {
  start_test "close-req SKILL 含步骤 2c（检查 req 级深度变更）"
  if ! grep -q "^### 步骤 2c" "$CLOSE_REQ_SKILL"; then
    _fail "close-req SKILL 缺步骤 2c"
    return
  fi
  if ! grep -q "本轮实现深度变更" "$CLOSE_REQ_SKILL"; then
    _fail "close-req 步骤 2c 应引用 solution.md「本轮实现深度变更」section"
    return
  fi
  pass_test
}

test_close_req_step_2c_skips_on_no_change() {
  start_test "close-req 步骤 2c 跳过条件：内容是「无变更」/ 留空 / section 不存在"
  if ! grep -E "无变更|留空|section 不存在" "$CLOSE_REQ_SKILL" >/dev/null; then
    _fail "close-req 步骤 2c 应描述跳过条件"
    return
  fi
  pass_test
}

test_close_req_step_2c_offers_pm_sync_choice() {
  start_test "close-req 步骤 2c 给 PM 提供 Y/N 选择（同步 / 不同步）"
  if ! grep -q "\[Y\] 同步" "$CLOSE_REQ_SKILL"; then
    _fail "close-req 步骤 2c 应有 [Y] 同步 选项"
    return
  fi
  if ! grep -q "\[N\] 不同步" "$CLOSE_REQ_SKILL"; then
    _fail "close-req 步骤 2c 应有 [N] 不同步 选项"
    return
  fi
  pass_test
}

test_close_req_step_2c_does_not_auto_modify_project_level() {
  start_test "close-req 步骤 2c：AI 不自动改项目级 CLAUDE.md，由 PM 手改"
  if ! grep -q "AI 不替 PM 改\|不让 AI 自动改\|不替 PM 改项目级" "$CLOSE_REQ_SKILL"; then
    _fail "close-req 步骤 2c 应明确说 AI 不自动改项目级 CLAUDE.md"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_solution_tmpl_has_depth_change_section
test_solution_tmpl_default_is_no_change
test_solution_tmpl_section_explains_when_to_fill
test_req_solution_skill_lists_section_in_order
test_req_solution_skill_when_to_fill_guidance
test_close_req_skill_has_step_2c
test_close_req_step_2c_skips_on_no_change
test_close_req_step_2c_offers_pm_sync_choice
test_close_req_step_2c_does_not_auto_modify_project_level

report_results "depth-change-section"
