#!/usr/bin/env bash
# 业务层偏差反推契约（4.5e）
#
# 验证：
# 1. task.md.tmpl「📁 历史档案」加「业务层偏差」表（默认「无」）
# 2. task-execute SKILL 步骤 6 含「两层分工」+ 业务层偏差表写入位置
# 3. doc-update SKILL Required Inputs 含 brief / analysis / solution / prd
# 4. doc-update SKILL 步骤 1 / 1.5 扫 PM 视图业务层偏差表
# 5. task-submit SKILL 引导 PM 走查时如发现 req 文档偏差填业务层偏差段
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_TMPL="$REPO_ROOT/templates/task.md.tmpl"
TASK_EXECUTE_SKILL="$REPO_ROOT/skills/task-execute/SKILL.md"
TASK_SUBMIT_SKILL="$REPO_ROOT/skills/task-submit/SKILL.md"
DOC_UPDATE_SKILL="$REPO_ROOT/skills/doc-update/SKILL.md"

test_task_tmpl_has_business_deviation_section() {
  start_test "task.md.tmpl 加「业务层偏差」结构化子段（4.5e）"
  if ! grep -q "^### 业务层偏差" "$TASK_TMPL"; then
    _fail "task.md.tmpl 缺「### 业务层偏差」section"
    return
  fi
  pass_test
}

test_task_tmpl_business_deviation_default_none() {
  start_test "task.md.tmpl 业务层偏差默认「无」"
  # 提取 ### 业务层偏差 section 至文件末尾或下一个 ## / ###
  local section
  section=$(awk '/^### 业务层偏差/{flag=1; next} /^### |^## /{flag=0} flag' "$TASK_TMPL")
  if ! echo "$section" | grep -q "^无$"; then
    _fail "task.md.tmpl 业务层偏差 section 默认应填「无」（独立行）"
    echo "section content:" >&2
    echo "$section" >&2
    return
  fi
  pass_test
}

test_task_tmpl_business_deviation_four_columns() {
  start_test "task.md.tmpl 业务层偏差表为四列：文档位置 / 文档原文 / 实证发现 / 建议改法"
  if ! grep -q "文档位置 | 文档原文 | 实证发现 | 建议改法" "$TASK_TMPL"; then
    _fail "task.md.tmpl 业务层偏差表头应为四列"
    return
  fi
  pass_test
}

test_task_execute_step6_two_layer_split() {
  start_test "task-execute SKILL 步骤 6 含「两层分工」表（工程层 vs 业务层）"
  if ! grep -q "两层分工" "$TASK_EXECUTE_SKILL"; then
    _fail "task-execute SKILL 步骤 6 应有「两层分工」说明"
    return
  fi
  if ! grep -q "工程层偏差" "$TASK_EXECUTE_SKILL"; then
    _fail "应有「工程层偏差」分类"
    return
  fi
  if ! grep -q "业务层偏差" "$TASK_EXECUTE_SKILL"; then
    _fail "应有「业务层偏差」分类"
    return
  fi
  pass_test
}

test_task_execute_step6_examples_cover_multiple_docs() {
  start_test "task-execute SKILL 步骤 6 示例覆盖多种文档（不只 module）"
  # 应有 brief / solution / module 等多种文档类型示例
  if ! grep -q "solution\.engineering\.md\|solution\.md" "$TASK_EXECUTE_SKILL"; then
    _fail "应有 solution.md 类示例"
    return
  fi
  if ! grep -q "brief\.md\|brief" "$TASK_EXECUTE_SKILL"; then
    _fail "应有 brief.md 类示例"
    return
  fi
  pass_test
}

test_task_execute_judgment_rule() {
  start_test "task-execute SKILL 步骤 6 含判断口诀（哪种偏差归哪层）"
  if ! grep -q "判断口诀\|判断.*口诀" "$TASK_EXECUTE_SKILL"; then
    _fail "task-execute SKILL 应有判断口诀帮 AI 决定写哪层"
    return
  fi
  pass_test
}

test_doc_update_required_inputs_extended() {
  start_test "doc-update Required Inputs 范围扩到 brief / analysis / solution / INDEX（v5 vp-1 砍 prd 后）"
  # v5 vp-1 砍 docs/prd.md 后，prd 不再是 doc-update 输入；改成 docs/modules/INDEX.md
  for doc in "brief\\.md" "analysis\\.md" "solution\\.md" "INDEX\\.md"; do
    if ! grep -q "$doc" "$DOC_UPDATE_SKILL"; then
      _fail "doc-update Required Inputs 应含 $doc"
      return
    fi
  done
  pass_test
}

test_doc_update_reads_business_deviation_table() {
  start_test "doc-update 步骤 1 从 PM 视图扫「业务层偏差」表"
  if ! grep -q "业务层偏差" "$DOC_UPDATE_SKILL"; then
    _fail "doc-update SKILL 应读 PM 视图「业务层偏差」表"
    return
  fi
  pass_test
}

test_doc_update_step15_dispatches_by_doc_type() {
  start_test "doc-update 步骤 1.5 按文档类型分流（module / 通用对账）"
  if ! grep -q "通用对账\|按文档类型分流" "$DOC_UPDATE_SKILL"; then
    _fail "doc-update SKILL 步骤 1.5 应按文档类型分流"
    return
  fi
  pass_test
}

test_task_submit_guides_pm_to_record_deviation() {
  start_test "task-submit SKILL 引导 PM 走查时填业务层偏差段"
  if ! grep -q "业务层偏差" "$TASK_SUBMIT_SKILL"; then
    _fail "task-submit SKILL 应引导 PM 把 req 文档偏差填到「业务层偏差」表"
    return
  fi
  if ! grep -q "对话里说.*会丢\|不要让 PM" "$TASK_SUBMIT_SKILL"; then
    _fail "task-submit SKILL 应警告 PM 别只在对话里说偏差（会丢）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_task_tmpl_has_business_deviation_section
test_task_tmpl_business_deviation_default_none
test_task_tmpl_business_deviation_four_columns
test_task_execute_step6_two_layer_split
test_task_execute_step6_examples_cover_multiple_docs
test_task_execute_judgment_rule
test_doc_update_required_inputs_extended
test_doc_update_reads_business_deviation_table
test_doc_update_step15_dispatches_by_doc_type
test_task_submit_guides_pm_to_record_deviation

report_results "business-deviation"
