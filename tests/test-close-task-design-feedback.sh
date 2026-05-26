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

# delta-9：§9.4 已收口为 relevance 二分 + 多去向 routing（不再是四类 sentiment 分流）。
# 本组测试改为断言新结构下「视觉规范 → DESIGN.md → close-task」routing 仍在。

test_pm_view_rules_has_routing_table() {
  start_test "input-flow §9.4 收口为 relevance 二分 + 多去向 routing"
  if ! grep -q "relevance 二分" "$PM_VIEW_RULES"; then
    _fail "§9.4 应含 relevance 二分（delta-3）"
    return
  fi
  if ! grep -q "多去向 routing" "$PM_VIEW_RULES"; then
    _fail "§9.4 应含多去向 routing 表（delta-9 收口）"
    return
  fi
  pass_test
}

test_pm_view_rules_design_consumer_is_close_task() {
  start_test "§9.4 routing：视觉 / 设计反馈 → DESIGN.md，消费者 close-task"
  local section
  section=$(awk '/^## 9.4/{flag=1; next} /^## /{flag=0} flag' "$PM_VIEW_RULES")
  if echo "$section" | grep -q "视觉.*DESIGN.md.*close-task"; then
    pass_test
  else
    _fail "§9.4 routing 表应有「视觉 / 设计 → docs/DESIGN.md → close-task」一行"
  fi
}

test_pm_view_rules_design_target_is_design_md() {
  start_test "§9.4 视觉规范写入位置是 docs/DESIGN.md"
  local section
  section=$(awk '/^## 9.4/{flag=1; next} /^## /{flag=0} flag' "$PM_VIEW_RULES")
  if echo "$section" | grep -q "DESIGN\.md\|docs/DESIGN"; then
    pass_test
  else
    _fail "§9.4 视觉规范条目应指向 docs/DESIGN.md"
  fi
}

test_pm_view_rules_product_rules_routing() {
  start_test "§9.4 routing：跨功能产品行为规则 → PRODUCT-RULES.md（delta-9）"
  local section
  section=$(awk '/^## 9.4/{flag=1; next} /^## /{flag=0} flag' "$PM_VIEW_RULES")
  if echo "$section" | grep -q "PRODUCT-RULES.md"; then
    pass_test
  else
    _fail "§9.4 routing 表应有「全项目跨功能产品行为规则 → PRODUCT-RULES.md」一行"
  fi
}

# -----------------------------------------------------------------
# templates/task.md.tmpl
# -----------------------------------------------------------------

# delta-3：v3 单文件 typed contract 的 PM 反馈段不再用
# [正向规则/反向约束/决策记录/视觉规范] 分类 enum + Y-rule/Y-task-note/N 选项
# （那些 close-task 内部记账标签）。改用 prose 路由说明 ——
# 视觉规范 → docs/DESIGN.md；跨功能产品规则 → docs/PRODUCT-RULES.md；
# task-local → 留本段由后续 task relevance 二分承接。

test_task_tmpl_design_feedback_routes_to_design_md() {
  start_test "task.md.tmpl PM 反馈段含 视觉规范 → docs/DESIGN.md 路由（delta-3 prose 路由）"
  if ! grep -q "视觉规范.*docs/DESIGN\.md\|视觉规范类 →" "$TASK_TMPL"; then
    _fail "task.md.tmpl PM 反馈段应说明视觉规范类反馈反推到 docs/DESIGN.md"
    return
  fi
  pass_test
}

test_task_tmpl_feedback_routes_cross_function_rules() {
  start_test "task.md.tmpl PM 反馈段含 跨功能产品规则 → docs/PRODUCT-RULES.md 路由（delta-9）"
  if ! grep -q "PRODUCT-RULES\.md" "$TASK_TMPL"; then
    _fail "task.md.tmpl PM 反馈段应说明跨功能产品规则反推到 docs/PRODUCT-RULES.md"
    return
  fi
  pass_test
}

test_task_tmpl_feedback_local_stays_for_relevance() {
  start_test "task.md.tmpl PM 反馈段说明 task-local 反馈留本段由后续 task relevance 二分承接"
  if ! grep -q "relevance 二分承接\|relevance 二分" "$TASK_TMPL"; then
    _fail "task.md.tmpl PM 反馈段应说明 task-local 反馈留本段、由后续 task-spec relevance 二分承接"
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

test_close_task_step_1_5_four_classes() {
  start_test "close-task 步骤 1.5：4 类分流（Y-baseline / Y-inventory / Y-task-fix / N-wrong-doc）"
  local section
  section=$(awk '/^### 步骤 1.5/{flag=1; next} /^### /{flag=0} flag' "$CLOSE_TASK_SKILL")
  for cls in "Y-baseline" "Y-inventory" "Y-task-fix" "N-wrong-doc"; do
    if ! echo "$section" | grep -q "$cls"; then
      _fail "步骤 1.5 应有 $cls 内部分类标签"
      return
    fi
  done
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

test_pm_view_rules_has_routing_table
test_pm_view_rules_design_consumer_is_close_task
test_pm_view_rules_design_target_is_design_md
test_pm_view_rules_product_rules_routing
test_task_tmpl_design_feedback_routes_to_design_md
test_task_tmpl_feedback_routes_cross_function_rules
test_task_tmpl_feedback_local_stays_for_relevance
test_close_task_has_step_1_5
test_close_task_step_1_5_in_correct_order
test_close_task_step_1_5_design_md_fallback
test_close_task_step_1_5_n_zero_skip
test_close_task_step_1_5_four_classes
test_close_task_step_1_5_forbids_silent_commit
test_close_task_step_3_hints_design_md_commit

report_results "close-task-design-feedback"
