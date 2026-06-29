#!/usr/bin/env bash
# test-design-shared-boundary.sh
#
# 验证 /pmai-design 的方法论边界：
#   T1: design-only / mixed 方法文件不留在 skills/_shared/
#   T2: 现役入口不再引用 _shared/module-questioning.md 或 _shared/info-design.md
#   T3: design / prd-writing / build-close 各自引用正确真相源
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ACTIVE_SEARCH_ROOTS=(
  "$REPO_ROOT/skills"
  "$REPO_ROOT/scripts"
  "$REPO_ROOT/templates"
)

_active_hits() {
  local pattern="$1"
  grep -RInE "$pattern" "${ACTIVE_SEARCH_ROOTS[@]}" 2>/dev/null \
    | grep -v "/skills/design/references/.*-legacy\\.md" \
    | grep -v "/skill-feedback/" \
    || true
}

test_design_only_files_not_in_shared() {
  start_test "T1: design-only / mixed 方法文件不留在 _shared"
  local offenders=()
  [ -e "$REPO_ROOT/skills/_shared/module-questioning.md" ] && offenders+=("skills/_shared/module-questioning.md")
  [ -e "$REPO_ROOT/skills/_shared/info-design.md" ] && offenders+=("skills/_shared/info-design.md")
  if [ "${#offenders[@]}" -gt 0 ]; then
    _fail "以下文件不应继续留在 _shared：${offenders[*]}"
    return
  fi
  pass_test
}

test_no_active_refs_to_old_shared_design_files() {
  start_test "T2: 现役入口不再引用旧 _shared 设计方法文件"
  local hits
  hits=$(_active_hits "_shared/(module-questioning|info-design)\\.md|skills/_shared/(module-questioning|info-design)\\.md")
  if [ -n "$hits" ]; then
    _fail "发现旧 _shared 设计方法引用：$hits"
    return
  fi
  pass_test
}

test_current_truth_sources_are_wired() {
  start_test "T3: design / prd-writing / build-close 引用当前真相源"
  if ! grep -q "skills/design/references/design-method.md" "$REPO_ROOT/skills/design/SKILL.md"; then
    _fail "skills/design/SKILL.md 未引用 design-method.md"
    return
  fi
  if ! grep -q "规格 4 问自检" "$REPO_ROOT/skills/prd-writing/references/writing-rules.md"; then
    _fail "prd-writing/references/writing-rules.md 缺规格 4 问自检"
    return
  fi
  if ! grep -q "skills/_shared/consistency-scan.md" "$REPO_ROOT/skills/build-close/SKILL.md"; then
    _fail "skills/build-close/SKILL.md 未显式引用 consistency-scan.md"
    return
  fi
  pass_test
}

test_design_only_files_not_in_shared
test_no_active_refs_to_old_shared_design_files
test_current_truth_sources_are_wired

report_results "design-shared-boundary"
