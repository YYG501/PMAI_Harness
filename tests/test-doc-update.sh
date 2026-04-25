#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

DOC_UPDATE_SKILL="$FRAMEWORK_ROOT/skills/doc-update/SKILL.md"

_contains() {
  local file="$1"
  local text="$2"
  grep -F -q -- "$text" "$file"
}

_assert_contains() {
  local file="$1"
  local text="$2"
  local desc="$3"
  if _contains "$file" "$text"; then
    return 0
  fi
  _fail "$desc: missing '$text'"
  sed -n '1,260p' "$file" >&2
  return 1
}

test_call_modes_and_reconciliation_preserved() {
  start_test "doc-update supports settlement mode and preserves reconciliation mode"

  _assert_contains "$DOC_UPDATE_SKILL" "对账模式（reconciliation mode）" "reconciliation call mode" || return
  _assert_contains "$DOC_UPDATE_SKILL" "沉淀模式（settlement mode）" "settlement call mode" || return
  _assert_contains "$DOC_UPDATE_SKILL" "### 步骤 1.5：判断是否涉及模块规格功能清单（对账模式保留）" "step 1.5 preserved" || return
  _assert_contains "$DOC_UPDATE_SKILL" "### 步骤 1.6：模块规格对账（对账模式保留）" "step 1.6 preserved" || return
  _assert_contains "$DOC_UPDATE_SKILL" "对账仍遵循最小修改原则" "old reconciliation behavior preserved" || return

  pass_test
}

test_settlement_four_situations() {
  start_test "doc-update settlement mode: 4-situation logic"

  _assert_contains "$DOC_UPDATE_SKILL" "### 步骤 1.7：模块规格沉淀（settlement mode）" "settlement branch heading" || return
  _assert_contains "$DOC_UPDATE_SKILL" "Item in task list but NOT in module spec" "ADD situation" || return
  _assert_contains "$DOC_UPDATE_SKILL" "**ADD**：静默执行" "ADD handling" || return
  _assert_contains "$DOC_UPDATE_SKILL" "Content identical" "SKIP situation" || return
  _assert_contains "$DOC_UPDATE_SKILL" "**SKIP**：不写入" "SKIP handling" || return
  _assert_contains "$DOC_UPDATE_SKILL" "Content different" "MODIFY situation" || return
  _assert_contains "$DOC_UPDATE_SKILL" "**MODIFY**：展示 diff，PM confirms each item" "MODIFY handling" || return
  _assert_contains "$DOC_UPDATE_SKILL" "Item in module spec but NOT in task list" "LEAVE UNCHANGED situation" || return
  _assert_contains "$DOC_UPDATE_SKILL" "**LEAVE UNCHANGED**：保留，不删除" "LEAVE handling" || return

  pass_test
}

test_composite_key_matching() {
  start_test "doc-update composite key matching"

  _assert_contains "$DOC_UPDATE_SKILL" "composite key" "composite key term" || return
  _assert_contains "$DOC_UPDATE_SKILL" "belonging module chapter" "belonging module chapter key" || return
  _assert_contains "$DOC_UPDATE_SKILL" 'task.md header field `**所属模块章节：**`' "task header field" || return
  _assert_contains "$DOC_UPDATE_SKILL" "level-3 feature name" "level-3 feature key" || return
  _assert_contains "$DOC_UPDATE_SKILL" 'section header `### N · name`' "task feature header" || return
  _assert_contains "$DOC_UPDATE_SKILL" '在 module spec 中定位 `### [module chapter]`，再查找其下 `#### N · [feature name]`' "module lookup" || return

  pass_test
}

test_multimodule_atomic_merge() {
  start_test "doc-update multi-module atomic merge with git temp branch"

  _assert_contains "$DOC_UPDATE_SKILL" "多模块 atomic merge（A3）" "atomic merge heading" || return
  _assert_contains "$DOC_UPDATE_SKILL" "Create temp branch" "create temp branch" || return
  _assert_contains "$DOC_UPDATE_SKILL" "Merge each module one by one" "merge each module" || return
  _assert_contains "$DOC_UPDATE_SKILL" "Any failure → delete temp branch → block close-task + error report" "failure rollback" || return
  _assert_contains "$DOC_UPDATE_SKILL" "当前 req 分支保持原 HEAD，不留下中间写入状态" "no intermediate state" || return
  _assert_contains "$DOC_UPDATE_SKILL" "All success → 将当前 req 分支 fast-forward 到临时分支结果" "fast-forward success" || return

  pass_test
}

test_failure_blocks_close_task() {
  start_test "doc-update DB2: all failures block close-task with recovery path"

  _assert_contains "$DOC_UPDATE_SKILL" "ALL failures block close-task" "all failures block" || return
  _assert_contains "$DOC_UPDATE_SKILL" "doc-update failed; close-task blocked" "blocked error prefix" || return
  _assert_contains "$DOC_UPDATE_SKILL" '`failure type`：只能使用 `write-file` / `content-conflict` / `key-match-failure` / `internal-bug`' "failure type list" || return
  _assert_contains "$DOC_UPDATE_SKILL" '`recovery path`' "recovery path field" || return
  _assert_contains "$DOC_UPDATE_SKILL" '重新运行 `/close-task`，`/close-task` 会 auto-resumes doc-update' "auto resume instruction" || return

  pass_test
}

test_summary_line_and_diff_link() {
  start_test "doc-update DX RU4: summary line plus diff link"

  _assert_contains "$DOC_UPDATE_SKILL" "Summary line + diff link（DX RU4）" "summary heading" || return
  _assert_contains "$DOC_UPDATE_SKILL" "已沉淀 N 条新增进 docs/modules/<module>.md (查看 diff: git diff HEAD~1 -- docs/modules/<module>.md)" "summary format" || return

  pass_test
}

test_infrastructure_skip() {
  start_test "doc-update infrastructure task skip detection"

  _assert_contains "$DOC_UPDATE_SKILL" '如果 `**所属模块：**` = `基础设施`' "infrastructure header detection" || return
  _assert_contains "$DOC_UPDATE_SKILL" "跳过模块规格沉淀，返回 success" "infra skip success" || return
  _assert_contains "$DOC_UPDATE_SKILL" "基础设施 task：跳过 docs/modules 沉淀，继续 close-task" "infra skip output" || return

  pass_test
}

test_batch3_todo_comment() {
  start_test "doc-update has Batch 3 skip-doc-update TODO marker"

  _assert_contains "$DOC_UPDATE_SKILL" "<!-- TODO Batch 3: depends on close-task --skip-doc-update flag -->" "Batch 3 TODO comment" || return

  pass_test
}

test_call_modes_and_reconciliation_preserved
test_settlement_four_situations
test_composite_key_matching
test_multimodule_atomic_merge
test_failure_blocks_close_task
test_summary_line_and_diff_link
test_infrastructure_skip
test_batch3_todo_comment

report_results "doc-update"
