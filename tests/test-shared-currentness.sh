#!/usr/bin/env bash
# test-shared-currentness.sh
#
# 验证 _shared 规则不再回流旧流程语义：
#   T1: project-questioning 不再声明 greenfield init-project 阶段 C 完整问卷
#   T2: banner-rules 不再使用旧 NEXT / stage 转换语义
#   T3: attachments-upload 的前缀映射与 helper 当前 allowlist 对齐
#   T4: PM-VIEW-RULES 不引用不存在的历史样例
#   T5: record-routing 声明 typed input + 模块引用登记
#   T6: term-detector markdown 头部不回退成断裂格式
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

test_project_questioning_current_callers() {
  start_test "T1: project-questioning 不再绑定 greenfield init-project 阶段 C"
  local file="$REPO_ROOT/skills/_shared/project-questioning.md"
  if grep -qE "阶段 C|全新项目首次起步|module-questioning" "$file"; then
    _fail "project-questioning.md 仍含旧 init/design-only 语义"
    return
  fi
  if grep -q "新项目走同一套" "$REPO_ROOT/skills/_internal/codebase-audit/SKILL.md"; then
    _fail "codebase-audit 仍声称新项目和 brownfield 方向讨论同一套"
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
      "$REPO_ROOT/skills/prd-writing/SKILL.md" \
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

test_project_questioning_current_callers
test_banner_rules_no_legacy_next_stage
test_attachments_prefix_mapping_matches_helper
test_pm_view_rules_no_missing_example_path
test_record_routing_typed_upload_current
test_term_detector_heading_clean

report_results "shared-currentness"
