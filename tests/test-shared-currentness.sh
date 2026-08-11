#!/usr/bin/env bash
# test-shared-currentness.sh
#
# 验证 _shared 规则不再回流旧流程语义：
#   T1: project-questioning 只服务成熟资料 / 已有代码接入，不再声明完整问卷
#   T2: banner-rules 不再使用旧 NEXT / stage 转换语义
#   T3: attachments-upload 的前缀映射与 helper 当前 allowlist 对齐
#   T4: PM-VIEW-RULES 不引用不存在的历史样例
#   T5: record-routing 声明 typed input + 模块引用登记
#   T6: term-detector markdown 头部不回退成断裂格式
#   T7: 所有 Skill preamble 尊重自定义 PMAI_HOME
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

test_project_questioning_current_callers() {
  start_test "T1: project-questioning 只核验成熟项目等价产品基线"
  local file="$REPO_ROOT/skills/_shared/project-questioning.md"
  if grep -qE "阶段 C|全新项目首次起步|module-questioning|/pmai-direction|skills/direction" "$file"; then
    _fail "project-questioning.md 仍含旧 init/design/direction 语义"
    return
  fi
  if ! grep -q '调用方.*资料目录分支.*codebase-audit step 4' "$file" \
     || ! grep -q '六项完整性标准' "$file" \
     || ! grep -q '/pmai-proposal' "$file"; then
    _fail "project-questioning.md 应只承担等价产品基线核验并把缺口转 Proposal"
    return
  fi
  if grep -qE "新项目走同一套|内联方向讨论|完整 5 节方向问卷" "$REPO_ROOT/skills/_internal/codebase-audit/SKILL.md"; then
    _fail "codebase-audit 不得用初始化问卷补产品方向"
    return
  fi
  pass_test
}

test_banner_rules_no_legacy_next_stage() {
  start_test "T2: banner-rules 不含旧 NEXT / stage 推进语义"
  local file="$REPO_ROOT/skills/_shared/pm-view/banner-rules.md"
  if grep -qE "PMAI ► NEXT|/pmai-next|scripts/_lib/stages.py|/pmai-status 推进|stage N" "$file"; then
    _fail "banner-rules.md 仍含旧 NEXT / stage 推进语义"
    return
  fi
  pass_test
}

test_attachments_prefix_mapping_matches_helper() {
  start_test "T3: attachments-upload 不再映射 build/review 前缀"
  local file="$REPO_ROOT/skills/_shared/pm-view/attachments-upload.md"
  if grep -qE '\| build \| `build`|\| 复审 \| `review`' "$file"; then
    _fail "attachments-upload.md 仍把 build/review 映射为 helper stage_prefix"
    return
  fi
  if ! grep -q '不支持 `build` / `review`' "$file"; then
    _fail "attachments-upload.md 应显式说明 build/review 不是有效前缀"
    return
  fi
  pass_test
}

test_pm_view_rules_no_missing_example_path() {
  start_test "T4: PM-VIEW-RULES 不引用不存在历史样例"
  if grep -q "department-group-role-design" "$REPO_ROOT/skills/_shared/PM-VIEW-RULES.md"; then
    _fail "PM-VIEW-RULES.md 仍引用不存在的 department-group-role-design 样例"
    return
  fi
  pass_test
}

test_record_routing_typed_upload_current() {
  start_test "T5: record-routing 使用 typed input + 模块引用登记"
  local file="$REPO_ROOT/skills/_shared/record-routing.md"
  local old_single_bucket_hits
  if grep -qE "docs/inputs/attachments/<产物前缀>|还不是项目级|尚未实现" "$file"; then
    _fail "record-routing.md 仍含 typed input 未实现或旧 attachments 单桶口径"
    return
  fi
  if ! grep -q "docs/inputs/<类别>/" "$file"; then
    _fail "record-routing.md 应声明附件按类型落 docs/inputs/<类别>/"
    return
  fi
  if ! grep -q "attachments_seen" "$file"; then
    _fail "record-routing.md 应说明当前模块引用登记在 attachments_seen"
    return
  fi
  if ! grep -q "input_category" "$REPO_ROOT/skills/_shared/pm-view/attachments-upload.md"; then
    _fail "attachments-upload.md 应要求 caller 传 input_category"
    return
  fi
  old_single_bucket_hits="$(
    grep -R -n "docs/inputs/attachments/" \
      "$REPO_ROOT/skills/_shared" \
      "$REPO_ROOT/skills/design/SKILL.md" \
      "$REPO_ROOT/skills/spec-writing/SKILL.md" \
      "$REPO_ROOT/skills/build-close/SKILL.md" \
      "$REPO_ROOT/templates" 2>/dev/null || true
  )"
  if [ -n "$old_single_bucket_hits" ]; then
    _fail "活跃 skill/template 仍把 docs/inputs/attachments/ 当作 PM-facing 归档目录"
    echo "$old_single_bucket_hits" >&2
    return
  fi
  pass_test
}

test_term_detector_heading_clean() {
  start_test "T6: term-detector 共享说明格式正常"
  local file="$REPO_ROOT/skills/_shared/term-detector/SKILL.md"
  if grep -q "\\*\\* 共享 detector" "$file"; then
    _fail "term-detector/SKILL.md 共享说明 markdown 仍是断裂格式"
    return
  fi
  pass_test
}

test_skill_preambles_respect_pmai_home() {
  start_test "T7: Skill preamble 尊重自定义 PMAI_HOME"
  local expected fixed_hits file
  local -a callers=(
    "$REPO_ROOT/skills/build-cancel/SKILL.md"
    "$REPO_ROOT/skills/quick-fix/SKILL.md"
    "$REPO_ROOT/skills/proposal/SKILL.md"
    "$REPO_ROOT/skills/record/SKILL.md"
    "$REPO_ROOT/skills/status/SKILL.md"
    "$REPO_ROOT/skills/_internal/codebase-audit/SKILL.md"
    "$REPO_ROOT/templates/CLAUDE.md.tmpl"
  )
  expected='source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"'

  for file in "${callers[@]}"; do
    if ! grep -qF "$expected" "$file"; then
      _fail "Skill preamble 未使用 PMAI_HOME fallback: $file"
      return
    fi
  done

  fixed_hits="$(find "$REPO_ROOT/skills" -name SKILL.md -type f -exec grep -nH -F 'source "$HOME/.pmai/scripts/skill-preamble.sh"' {} + 2>/dev/null || true)"
  if [ -n "$fixed_hits" ]; then
    _fail "Skill 仍写死 ~/.pmai，覆盖自定义 PMAI_HOME"
    echo "$fixed_hits" >&2
    return
  fi
  pass_test
}

test_project_questioning_current_callers
test_banner_rules_no_legacy_next_stage
test_attachments_prefix_mapping_matches_helper
test_pm_view_rules_no_missing_example_path
test_record_routing_typed_upload_current
test_term_detector_heading_clean
test_skill_preambles_respect_pmai_home

report_results "shared-currentness"
