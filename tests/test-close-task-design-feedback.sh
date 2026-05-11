#!/usr/bin/env bash
# close-task 步骤 1.5「视觉规范反馈反推 DESIGN.md」契约测试
#
# 验证：
# 1. PM-VIEW-RULES §9.4 含第四类「视觉规范」+ close-task 作消费者
# 2. PM-VIEW-RULES §9.4 含禁止"塞反向约束"反模式 + task-001 实证
# 3. templates/task.md.tmpl 反馈分类 enum 含「视觉规范」
# 4. templates/task.md.tmpl 反馈规则 block 含 视觉规范 → docs/DESIGN.md
# 5. close-task SKILL 含步骤 1.5（在步骤 1 后、步骤 2 前）
# 6. 步骤 1.5：DESIGN.md 不存在 fallback / N=0 跳过 / 三选一 / 禁止 silent commit
# 7. close-task 步骤 3 含 DESIGN.md commit hint
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PM_VIEW_RULES="$REPO_ROOT/skills/_shared/pm-view/input-flow.md"
TASK_TMPL="$REPO_ROOT/templates/task.md.tmpl"
CLOSE_TASK_SKILL="$REPO_ROOT/skills/close-task/SKILL.md"

# -----------------------------------------------------------------
# PM-VIEW-RULES §9.4
# -----------------------------------------------------------------

test_pm_view_rules_has_fourth_category() {
  start_test "PM-VIEW-RULES §9.4 含第四类「视觉规范」"
  if ! grep -q "四类分流\|四类" "$PM_VIEW_RULES"; then
    _fail "§9.4 应升级为四类分流（标题或正文含「四类」）"
    return
  fi
  if ! grep -q "视觉规范" "$PM_VIEW_RULES"; then
    _fail "§9.4 应有「视觉规范」分类条目"
    return
  fi
  pass_test
}

test_pm_view_rules_design_consumer_is_close_task() {
  start_test "PM-VIEW-RULES §9.4 视觉规范的消费者是 close-task"
  # 提取 §9.4 section
  local section
  section=$(awk '/^## 9.4/{flag=1; next} /^## /{flag=0} flag' "$PM_VIEW_RULES")
  if ! echo "$section" | grep -q "视觉规范.*close-task\|close-task.*视觉规范"; then
    if ! echo "$section" | grep -q "视觉规范"; then
      _fail "§9.4 缺视觉规范行"
      return
    fi
    # 视觉规范行存在但消费者列没写 close-task
    if ! echo "$section" | grep -A1 "视觉规范" | grep -q "close-task"; then
      _fail "§9.4 视觉规范行的消费者列应是 close-task"
      return
    fi
  fi
  pass_test
}

test_pm_view_rules_design_target_is_design_md() {
  start_test "PM-VIEW-RULES §9.4 视觉规范写入位置是 docs/DESIGN.md"
  local section
  section=$(awk '/^## 9.4/{flag=1; next} /^## /{flag=0} flag' "$PM_VIEW_RULES")
  if ! echo "$section" | grep -q "DESIGN\.md\|docs/DESIGN"; then
    _fail "§9.4 视觉规范条目应指向 docs/DESIGN.md"
    return
  fi
  pass_test
}

test_pm_view_rules_forbids_into_negative_constraint() {
  start_test "PM-VIEW-RULES §9.4 含禁止「视觉规范塞反向约束」反模式"
  local section
  section=$(awk '/^## 9.4/{flag=1; next} /^## /{flag=0} flag' "$PM_VIEW_RULES")
  if ! echo "$section" | grep -q "视觉规范.*反向约束\|塞.*反向约束\|塞到.*易错点"; then
    _fail "§9.4 应禁止把视觉规范类反馈塞到反向约束 / 工程合同 §6 易错点"
    return
  fi
  if ! echo "$section" | grep -q "task-001"; then
    _fail "§9.4 应引用 task-001 R6 的实证（沉淀缺失反模式）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# templates/task.md.tmpl
# -----------------------------------------------------------------

test_task_tmpl_classification_includes_design() {
  start_test "task.md.tmpl 反馈分类 enum 含「视觉规范」"
  if ! grep -q "正向规则.*反向约束.*决策记录.*视觉规范\|视觉规范.*正向规则" "$TASK_TMPL"; then
    _fail "task.md.tmpl 反馈分类 enum 应是 [正向规则 / 反向约束 / 决策记录 / 视觉规范]"
    return
  fi
  pass_test
}

test_task_tmpl_design_rule_routes_to_design_md() {
  start_test "task.md.tmpl 反馈规则 block 含 视觉规范 → docs/DESIGN.md"
  if ! grep -q "视觉规范.*DESIGN\.md\|视觉规范.*docs/DESIGN" "$TASK_TMPL"; then
    _fail "task.md.tmpl 应说明视觉规范类反馈反推到 docs/DESIGN.md"
    return
  fi
  if ! grep -q "Y-rule\|Y-task-note" "$TASK_TMPL"; then
    _fail "task.md.tmpl 应说明三选一选项（Y-rule / Y-task-note / N）"
    return
  fi
  pass_test
}

test_task_tmpl_warns_against_negative_constraint_misuse() {
  start_test "task.md.tmpl 含警告「视觉规范禁塞反向约束」"
  if ! grep -q "视觉规范.*禁止.*反向约束\|视觉规范.*禁.*塞" "$TASK_TMPL"; then
    _fail "task.md.tmpl 应警告视觉规范类反馈不要错塞到反向约束"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# close-task SKILL.md
# -----------------------------------------------------------------

test_close_task_has_step_1_5() {
  start_test "close-task SKILL 含步骤 1.5（视觉规范反馈反推 DESIGN.md）"
  if ! grep -q "^### 步骤 1.5" "$CLOSE_TASK_SKILL"; then
    _fail "close-task SKILL 缺「### 步骤 1.5」section"
    return
  fi
  if ! grep -q "视觉规范反馈反推 DESIGN" "$CLOSE_TASK_SKILL"; then
    _fail "步骤 1.5 标题应含「视觉规范反馈反推 DESIGN.md」"
    return
  fi
  pass_test
}

test_close_task_step_1_5_in_correct_order() {
  start_test "close-task 步骤 1.5 在步骤 1 之后、步骤 2 之前"
  local step1_line step1_5_line step2_line
  step1_line=$(grep -n "^### 步骤 1：" "$CLOSE_TASK_SKILL" | head -1 | cut -d: -f1)
  step1_5_line=$(grep -n "^### 步骤 1.5" "$CLOSE_TASK_SKILL" | head -1 | cut -d: -f1)
  step2_line=$(grep -n "^### 步骤 2：" "$CLOSE_TASK_SKILL" | head -1 | cut -d: -f1)
  if [ -z "$step1_line" ] || [ -z "$step1_5_line" ] || [ -z "$step2_line" ]; then
    _fail "步骤 1 / 1.5 / 2 之一未找到"
    return
  fi
  if [ "$step1_line" -ge "$step1_5_line" ] || [ "$step1_5_line" -ge "$step2_line" ]; then
    _fail "顺序错误：step1=$step1_line, step1.5=$step1_5_line, step2=$step2_line"
    return
  fi
  pass_test
}

test_close_task_step_1_5_design_md_fallback() {
  start_test "close-task 步骤 1.5：docs/DESIGN.md 不存在时 fallback 跳过"
  local section
  section=$(awk '/^### 步骤 1.5/{flag=1; next} /^### /{flag=0} flag' "$CLOSE_TASK_SKILL")
  if ! echo "$section" | grep -q 'DESIGN_MD\|DESIGN.md.*不存在\|! -f.*DESIGN'; then
    _fail "步骤 1.5 应有 DESIGN.md 不存在 fallback 检查"
    return
  fi
  if ! echo "$section" | grep -q "跳过\|skip\|进入步骤 2"; then
    _fail "步骤 1.5 fallback 应跳过本步进步骤 2"
    return
  fi
  pass_test
}

test_close_task_step_1_5_n_zero_skip() {
  start_test "close-task 步骤 1.5：N=0 候选时跳过本步"
  local section
  section=$(awk '/^### 步骤 1.5/{flag=1; next} /^### /{flag=0} flag' "$CLOSE_TASK_SKILL")
  if ! echo "$section" | grep -q "N = 0\|N=0\|候选数 = 0"; then
    _fail "步骤 1.5 应明确 N=0 跳过本步"
    return
  fi
  pass_test
}

test_close_task_step_1_5_three_options() {
  start_test "close-task 步骤 1.5：PM 三选一（Y-rule / Y-task-note / N）"
  local section
  section=$(awk '/^### 步骤 1.5/{flag=1; next} /^### /{flag=0} flag' "$CLOSE_TASK_SKILL")
  if ! echo "$section" | grep -q "Y-rule"; then
    _fail "步骤 1.5 应有 Y-rule 选项"
    return
  fi
  if ! echo "$section" | grep -q "Y-task-note"; then
    _fail "步骤 1.5 应有 Y-task-note 选项"
    return
  fi
  if ! echo "$section" | grep -q '\*\*N\*\*\|选项.*N\b\|`N`\|分类 `N`'; then
    _fail "步骤 1.5 应有 N 内部分类标签（AI 误分类时改正）"
    return
  fi
  pass_test
}

test_close_task_step_1_5_forbids_silent_commit() {
  start_test "close-task 步骤 1.5：禁止 silent commit DESIGN.md"
  local section
  section=$(awk '/^### 步骤 1.5/{flag=1; next} /^### /{flag=0} flag' "$CLOSE_TASK_SKILL")
  if ! echo "$section" | grep -q "禁止.*silent.*commit\|禁止.*自动.*commit\|不 commit\|未 commit"; then
    _fail "步骤 1.5 应禁止 silent commit DESIGN.md（PM 显式审 diff 后自己 commit）"
    return
  fi
  pass_test
}

test_close_task_step_3_hints_design_md_commit() {
  start_test "close-task SKILL 含 DESIGN.md commit hint（步骤 1.5 patch 过时）"
  # 两 phase 改造后 hint 落在 Phase 2 收尾段（无固定步骤号），改 grep 整个 SKILL
  if ! grep -q "docs/DESIGN.md" "$CLOSE_TASK_SKILL"; then
    _fail "SKILL 应提示 PM commit docs/DESIGN.md（步骤 1.5 沉淀过时）"
    return
  fi
  if ! grep -q 'docs(DESIGN)' "$CLOSE_TASK_SKILL"; then
    _fail "SKILL 应给 commit message 模板（docs(DESIGN): ...）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_pm_view_rules_has_fourth_category
test_pm_view_rules_design_consumer_is_close_task
test_pm_view_rules_design_target_is_design_md
test_pm_view_rules_forbids_into_negative_constraint
test_task_tmpl_classification_includes_design
test_task_tmpl_design_rule_routes_to_design_md
test_task_tmpl_warns_against_negative_constraint_misuse
test_close_task_has_step_1_5
test_close_task_step_1_5_in_correct_order
test_close_task_step_1_5_design_md_fallback
test_close_task_step_1_5_n_zero_skip
test_close_task_step_1_5_three_options
test_close_task_step_1_5_forbids_silent_commit
test_close_task_step_3_hints_design_md_commit

report_results "close-task-design-feedback"
