#!/usr/bin/env bash
# test-roadmap-guidance.sh
#
# 验证 ROADMAP "历史 + 未来一张表" 引导覆盖到位（PM 实测踩坑修复）：
#   T1: _shared/project-questioning.md §5.2 含"历史 + 未来一张表"明示
#   T2: §5.2 含三态 (done / active / planned) 全列
#   T3: §5.2 含"requirements/closed" 扫描指引（老项目首次补 done 行）
#   T4: /pmai-project-solution SKILL.md B 场景表格行含"closed" + "done 行"指引
#   T5: §10.2 步骤总览 B 行含"closed"提示
#
# 背景：PM 实测跑 /pmai-project-solution B 场景写出的 ROADMAP 只含 planned 行，
# 漏 7 个已 close 的 req 作 done 行。模板 HTML 注释虽有三态说明，但 §5.2
# 写作规则只说"计划态 + planned"导致 AI 注意力没到模板注释。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
QUESTIONING="$REPO_ROOT/skills/_shared/project-questioning.md"
SKILL_SOLUTION="$REPO_ROOT/skills/project-solution/SKILL.md"

# -----------------------------------------------------------------
test_section_5_2_says_history_plus_future() {
  start_test "T1: §5.2 含\"历史 + 未来一张表\"明示"
  if ! grep -q '历史 + 未来一张表' "$QUESTIONING"; then
    _fail "_shared/project-questioning.md §5.2 缺\"历史 + 未来一张表\"措辞"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_section_5_2_lists_three_states() {
  start_test "T2: §5.2 含三态 done / active / planned"
  # 提取 §5.2 段（到下一个 §5.3 之前）
  local section
  section=$(awk '/^### §5\.2 ROADMAP\.md/,/^### §5\.3/' "$QUESTIONING")
  for state in done active planned; do
    if ! echo "$section" | grep -qE "\`$state\`"; then
      _fail "§5.2 缺三态之一: \`$state\`"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
test_section_5_2_says_scan_closed() {
  start_test "T3: §5.2 含 requirements/closed 扫描指引"
  local section
  section=$(awk '/^### §5\.2 ROADMAP\.md/,/^### §5\.3/' "$QUESTIONING")
  if ! echo "$section" | grep -q 'requirements/closed'; then
    _fail "§5.2 缺 requirements/closed 扫描指引（老项目首次补 done 行的路径）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_b_scenario_table_row_has_closed_done_guidance() {
  start_test "T4: project-solution B 场景表格行含 closed + done 行 指引"
  # 提取 B 场景表格行
  local row
  row=$(grep -E '^\| \*\*B 产品路线规划\*\*' "$SKILL_SOLUTION" || true)
  if [ -z "$row" ]; then
    _fail "找不到 B 产品路线规划表格行"
    return
  fi
  if ! echo "$row" | grep -q 'closed'; then
    _fail "B 场景表格行缺 closed 扫描指引"
    return
  fi
  if ! echo "$row" | grep -q 'done 行'; then
    _fail "B 场景表格行缺\"done 行\"明示"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_section_10_2_step_overview_has_closed_hint() {
  start_test "T5: §10.2 步骤总览 B 行含 closed 提示"
  local row
  row=$(grep -E 'B 产品路线规划：' "$QUESTIONING" || true)
  if [ -z "$row" ]; then
    _fail "找不到 §10.2 B 产品路线规划 步骤行"
    return
  fi
  if ! echo "$row" | grep -q 'closed'; then
    _fail "§10.2 B 步骤行缺 closed 提示（防 AI 漏写历史 done）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_section_5_2_says_history_plus_future
test_section_5_2_lists_three_states
test_section_5_2_says_scan_closed
test_b_scenario_table_row_has_closed_done_guidance
test_section_10_2_step_overview_has_closed_hint

report_results "roadmap-guidance"
