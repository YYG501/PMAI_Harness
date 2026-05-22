#!/usr/bin/env bash
# 文档偏差反推契约（4.5e；delta-3 单文件塌缩后更新）
#
# delta-3：旧「业务层偏差 vs 工程层偏差」两层分工 + 双文件投递 已塌缩为
# 单文件 typed contract 审计区「📋 文档偏差」一处四列表（文档位置 / 文档原文 /
# 实际实现 / 建议改法）。本套件断言新单一偏差表结构。
#
# 验证：
# 1. task.md.tmpl 审计区含「📋 文档偏差」表（默认「无」）
# 2. task-execute SKILL 步骤 6 写审计区「📋 文档偏差」（v2 兼容仍保留两层分工说明）
# 3. doc-update SKILL Required Inputs 含 brief / analysis / solution / prd
# 4. doc-update SKILL 扫审计区「📋 文档偏差」表
# 5. task-submit SKILL 引导 PM 走查时如发现 req 文档偏差填「📋 文档偏差」表
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_TMPL="$REPO_ROOT/templates/task.md.tmpl"
TASK_EXECUTE_SKILL="$REPO_ROOT/skills/task-execute/SKILL.md"
TASK_SUBMIT_SKILL="$REPO_ROOT/skills/task-submit/SKILL.md"
DOC_UPDATE_SKILL="$REPO_ROOT/skills/doc-update/SKILL.md"

test_task_tmpl_has_doc_deviation_section() {
  start_test "task.md.tmpl 审计区含「📋 文档偏差」section（delta-3 单一偏差表）"
  if ! grep -q "^## 📋 文档偏差" "$TASK_TMPL"; then
    _fail "task.md.tmpl 缺「## 📋 文档偏差」section"
    return
  fi
  pass_test
}

test_task_tmpl_doc_deviation_default_none() {
  start_test "task.md.tmpl 文档偏差默认「无」"
  # 提取 ## 📋 文档偏差 section 至下一个 ## / ###
  local section
  section=$(awk '/^## 📋 文档偏差/{flag=1; next} /^### |^## /{flag=0} flag' "$TASK_TMPL")
  if ! echo "$section" | grep -q "^无$"; then
    _fail "task.md.tmpl 文档偏差 section 默认应填「无」（独立行）"
    echo "section content:" >&2
    echo "$section" >&2
    return
  fi
  pass_test
}

test_task_tmpl_doc_deviation_four_columns() {
  start_test "task.md.tmpl 文档偏差表为四列：文档位置 / 文档原文 / 实际实现 / 建议改法"
  if ! grep -q "文档位置 | 文档原文 | 实际实现 | 建议改法" "$TASK_TMPL"; then
    _fail "task.md.tmpl 文档偏差表头应为四列"
    return
  fi
  pass_test
}

test_task_execute_step6_single_deviation_table() {
  start_test "task-execute SKILL 步骤 6 写审计区「📋 文档偏差」单一偏差表（delta-3）"
  # delta-3 单文件塌缩：偏差统一写审计区一处四列表
  if ! grep -q "审计区「📋 文档偏差」" "$TASK_EXECUTE_SKILL"; then
    _fail "task-execute SKILL 步骤 6 应写审计区「📋 文档偏差」"
    return
  fi
  if ! grep -q "文档位置 / 文档原文 / 实际实现 / 建议改法" "$TASK_EXECUTE_SKILL"; then
    _fail "应说明四列：文档位置 / 文档原文 / 实际实现 / 建议改法"
    return
  fi
  # v2 旧双文件 task 兼容：仍保留两层分工说明
  if ! grep -q "两层分工" "$TASK_EXECUTE_SKILL"; then
    _fail "应保留 v2 兼容的「两层分工」说明"
    return
  fi
  pass_test
}

test_task_execute_step6_examples_cover_multiple_docs() {
  start_test "task-execute SKILL 步骤 6 示例覆盖多种文档（不只 module）"
  # delta-3：task-spec 读 prd.md + implementation-design.md，偏差示例覆盖这些
  if ! grep -q "implementation-design\.md" "$TASK_EXECUTE_SKILL"; then
    _fail "应有 implementation-design.md 类示例"
    return
  fi
  if ! grep -q "prd\.md" "$TASK_EXECUTE_SKILL"; then
    _fail "应有 prd.md 类示例"
    return
  fi
  pass_test
}

test_doc_update_required_inputs_extended() {
  start_test "doc-update Required Inputs 覆盖 analysis / prd / implementation-design / INDEX（delta-2+3 后）"
  # delta-2+3：task-spec 读 prd.md + implementation-design.md；doc-update Required
  # Inputs 随之指向 analysis / prd / implementation-design / modules INDEX。
  for doc in "analysis\\.md" "prd\\.md" "implementation-design\\.md" "INDEX\\.md"; do
    if ! grep -q "$doc" "$DOC_UPDATE_SKILL"; then
      _fail "doc-update Required Inputs 应含 $doc"
      return
    fi
  done
  pass_test
}

test_doc_update_reads_doc_deviation_table() {
  start_test "doc-update 从审计区「📋 文档偏差」表读偏差记录（delta-3 单一偏差表）"
  if ! grep -q "审计区「📋 文档偏差」" "$DOC_UPDATE_SKILL"; then
    _fail "doc-update SKILL 应读审计区「📋 文档偏差」表"
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
  start_test "task-submit SKILL 引导 PM 走查时填「📋 文档偏差」表"
  # delta-3：v3 偏差统一填审计区「📋 文档偏差」表（v2 旧 task 仍提业务层偏差）
  if ! grep -q "文档偏差" "$TASK_SUBMIT_SKILL"; then
    _fail "task-submit SKILL 应引导 PM 把 req 文档偏差填到「📋 文档偏差」表"
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

test_task_tmpl_has_doc_deviation_section
test_task_tmpl_doc_deviation_default_none
test_task_tmpl_doc_deviation_four_columns
test_task_execute_step6_single_deviation_table
test_task_execute_step6_examples_cover_multiple_docs
test_doc_update_required_inputs_extended
test_doc_update_reads_doc_deviation_table
test_doc_update_step15_dispatches_by_doc_type
test_task_submit_guides_pm_to_record_deviation

report_results "business-deviation"
