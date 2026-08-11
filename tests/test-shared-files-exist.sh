#!/usr/bin/env bash
# test-shared-files-exist.sh
#
# 验证被 @读 的 _shared 文件存在 + 内容完整（D-iv M1 vp-5a；review C-5 / 防 R10 _shared 缺失）：
#   T1: skills/_shared/project-questioning.md 存在 + 含等价产品基线核验与 Proposal 出口
#   T2: skills/_shared/PM-VIEW-RULES.md 存在（7 个 skill 引用）
#   T3: skills/_shared/pm-view/ 目录存在 + 含子文件
#   T4: SKILL.md 里所有 @读 _shared/* 引用 → 对应文件必须存在（前向链接完整）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHARED_DIR="$REPO_ROOT/skills/_shared"

# -----------------------------------------------------------------
# T1: project-questioning.md 存在 + 含等价产品基线核验与 Proposal 出口
# -----------------------------------------------------------------
test_project_questioning_exists() {
  start_test "T1: project-questioning.md 存在 + 含基线核验与 Proposal 出口"
  if [ ! -f "$SHARED_DIR/project-questioning.md" ]; then
    _fail "skills/_shared/project-questioning.md 不存在"
    return
  fi
  if ! grep -q "§3 六项完整性标准" "$SHARED_DIR/project-questioning.md"; then
    _fail "project-questioning.md 缺六项完整性标准"
    return
  fi
  if ! grep -q "§6 不通过时的出口" "$SHARED_DIR/project-questioning.md" \
     || ! grep -q '/pmai-proposal' "$SHARED_DIR/project-questioning.md"; then
    _fail "project-questioning.md 缺 Proposal 出口"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T2: PM-VIEW-RULES.md 存在
# -----------------------------------------------------------------
test_pm_view_rules_exists() {
  start_test "T2: skills/_shared/PM-VIEW-RULES.md 存在"
  if [ ! -f "$SHARED_DIR/PM-VIEW-RULES.md" ]; then
    _fail "skills/_shared/PM-VIEW-RULES.md 不存在"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T3: pm-view/ 目录存在 + 含子文件
# -----------------------------------------------------------------
test_pm_view_dir_exists() {
  start_test "T3: skills/_shared/pm-view/ 目录存在 + 含子文件"
  if [ ! -d "$SHARED_DIR/pm-view" ]; then
    _fail "skills/_shared/pm-view/ 目录不存在"
    return
  fi
  local file_count
  file_count=$(find "$SHARED_DIR/pm-view" -maxdepth 1 -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$file_count" -lt 1 ]; then
    _fail "skills/_shared/pm-view/ 没有 .md 子文件"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T4: SKILL.md 里所有 @读 _shared/<path> 引用 → 对应文件必须存在
# -----------------------------------------------------------------
test_all_shared_references_resolve() {
  start_test "T4: SKILL.md 里所有 @读 _shared/* 引用对应文件存在（前向链接完整）"
  local broken_refs=()
  # 简化：grep "_shared/<filename>.md" 模式，提取文件名，逐个 test -f 验证
  # 限定在 skills/*/SKILL.md（不扫 _shared 自己）
  while IFS= read -r line; do
    # 提取 _shared/<path>.md 形式（含子目录）
    local ref_path
    ref_path=$(echo "$line" | grep -oE '_shared/[a-zA-Z0-9_/-]+\.md' | head -1)
    [ -z "$ref_path" ] && continue
    # 跳过模糊引用（_shared/pm-view 不含 .md 后缀的目录指代）
    if [ ! -f "$REPO_ROOT/skills/$ref_path" ]; then
      broken_refs+=("$ref_path")
    fi
  done < <(grep -rh "_shared/[a-zA-Z0-9_/-]*\.md" "$REPO_ROOT/skills/"*/SKILL.md 2>/dev/null | sort -u)

  if [ "${#broken_refs[@]}" -gt 0 ]; then
    _fail "以下 _shared 引用文件不存在：${broken_refs[*]}"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_project_questioning_exists
test_pm_view_rules_exists
test_pm_view_dir_exists
test_all_shared_references_resolve

report_results "shared-files-exist"
