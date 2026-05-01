#!/usr/bin/env bash
# 工程结构约束 schema → 模板 派生 golden test（4.5a）
#
# 验证：
# 1. schema 文件 + derive 脚本 + 两份派生模板 都存在
# 2. derive --check 模式：现有模板与 schema 派生结果一致（防漂移）
# 3. schema 缺字段 / 非法值 → derive 校验失败 exit 2
# 4. CLAUDE.md.tmpl 含 STRUCTURE_CONSTRAINTS placeholder
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCHEMA="$REPO_ROOT/templates/工程结构约束.schema.json"
DERIVE="$REPO_ROOT/scripts/derive-structure-templates.py"
PROTO_TMPL="$REPO_ROOT/templates/工程结构约束-prototype.md"
SYS_TMPL="$REPO_ROOT/templates/工程结构约束-system.md"
CUSTOM_TMPL="$REPO_ROOT/templates/工程结构约束-custom.md"
CLAUDE_TMPL="$REPO_ROOT/templates/CLAUDE.md.tmpl"

test_schema_exists() {
  start_test "schema file exists"
  if [ ! -f "$SCHEMA" ]; then
    _fail "schema 文件不存在: $SCHEMA"
    return
  fi
  pass_test
}

test_derive_script_exists() {
  start_test "derive 脚本存在 + 可执行"
  if [ ! -f "$DERIVE" ]; then
    _fail "derive 脚本不存在: $DERIVE"
    return
  fi
  if [ ! -x "$DERIVE" ]; then
    _fail "derive 脚本无执行权限: $DERIVE"
    return
  fi
  pass_test
}

test_both_templates_derived() {
  start_test "三份派生模板都存在（prototype / system / custom）"
  for tmpl in "$PROTO_TMPL" "$SYS_TMPL" "$CUSTOM_TMPL"; do
    if [ ! -f "$tmpl" ]; then
      _fail "派生模板不存在: $tmpl"
      return
    fi
  done
  pass_test
}

test_templates_have_auto_generated_marker() {
  start_test "派生模板含 AUTO-GENERATED marker（防 PM 手改）"
  for tmpl in "$PROTO_TMPL" "$SYS_TMPL" "$CUSTOM_TMPL"; do
    if ! grep -q "AUTO-GENERATED FROM" "$tmpl"; then
      _fail "$tmpl 缺 AUTO-GENERATED marker"
      return
    fi
  done
  pass_test
}

test_prototype_template_has_depth_prose() {
  start_test "prototype 模板含「实现深度指引」prose 段（4.5d.2）"
  if ! grep -q "实现深度指引" "$PROTO_TMPL"; then
    _fail "prototype 模板缺「实现深度指引」section"
    return
  fi
  for label in "数据层" "权限层" "API 契约" "测试" "边界态" "多端覆盖" "演示路径"; do
    if ! grep -q "$label" "$PROTO_TMPL"; then
      _fail "prototype 模板缺「$label」prose"
      return
    fi
  done
  pass_test
}

test_system_template_has_depth_prose() {
  start_test "system 模板含「实现深度指引」prose 段（4.5d.2）"
  if ! grep -q "实现深度指引" "$SYS_TMPL"; then
    _fail "system 模板缺「实现深度指引」section"
    return
  fi
  pass_test
}

test_custom_template_has_pm_fill_skeleton() {
  start_test "custom 模板含 PM 自由编辑骨架（无预设深度，4.5d.2）"
  if ! grep -q "_PM 填_" "$CUSTOM_TMPL"; then
    _fail "custom 模板应含「_PM 填_」骨架提示"
    return
  fi
  if ! grep -q "代码组织" "$CUSTOM_TMPL"; then
    _fail "custom 模板应含「代码组织」section"
    return
  fi
  if ! grep -q "实现深度指引" "$CUSTOM_TMPL"; then
    _fail "custom 模板应含「实现深度指引」section"
    return
  fi
  pass_test
}

test_check_mode_passes_for_synced() {
  start_test "derive --check：当前模板与 schema 一致"
  if ! python3 "$DERIVE" --check >/tmp/derive-check.out 2>&1; then
    _fail "schema vs 模板 漂移（请跑 \`python3 scripts/derive-structure-templates.py\` 重派生并 commit）"
    cat /tmp/derive-check.out >&2
    return
  fi
  pass_test
  rm -f /tmp/derive-check.out
}

test_check_mode_detects_drift() {
  start_test "derive --check 检测到模板漂移时 exit 1"
  # 备份 + 改坏 prototype 模板
  local backup
  backup=$(mktemp)
  cp "$PROTO_TMPL" "$backup"
  echo "DRIFTED" >> "$PROTO_TMPL"

  if python3 "$DERIVE" --check >/tmp/drift.out 2>&1; then
    _fail "drift 注入后 check 居然 pass，意外"
    cp "$backup" "$PROTO_TMPL"
    rm -f "$backup"
    return
  fi

  # restore
  cp "$backup" "$PROTO_TMPL"
  rm -f "$backup" /tmp/drift.out
  pass_test
}

test_invalid_schema_rejected() {
  start_test "schema 字段非法时 derive 校验失败 exit 2"
  local tmp_schema
  tmp_schema=$(mktemp)
  cat > "$tmp_schema" <<'EOF'
{
  "schema_version": 99,
  "signals": {},
  "scan_excludes": [],
  "scan_roots_default": []
}
EOF

  # 用 Python 直接调 validate（绕过文件路径硬编码）
  rc=$(python3 -c "
import sys, json
sys.path.insert(0, '$REPO_ROOT/scripts')
import importlib.util
spec = importlib.util.spec_from_file_location('derive', '$DERIVE')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
schema = json.load(open('$tmp_schema'))
errors = mod.validate_schema(schema)
print('FAIL' if errors else 'PASS')
")
  rm -f "$tmp_schema"
  if [ "$rc" != "FAIL" ]; then
    _fail "非法 schema 应被拒，但 validate_schema 返回空 errors"
    return
  fi
  pass_test
}

test_claude_tmpl_has_placeholder() {
  start_test "CLAUDE.md.tmpl 含 STRUCTURE_CONSTRAINTS placeholder"
  if ! grep -q '{{STRUCTURE_CONSTRAINTS}}' "$CLAUDE_TMPL"; then
    _fail "CLAUDE.md.tmpl 缺 {{STRUCTURE_CONSTRAINTS}} placeholder"
    return
  fi
  if ! grep -q '## 工程结构约束' "$CLAUDE_TMPL"; then
    _fail "CLAUDE.md.tmpl 缺 ## 工程结构约束 section"
    return
  fi
  pass_test
}

test_claude_tmpl_documents_unknown_branch() {
  start_test "CLAUDE.md.tmpl placeholder 注释提到 unknown 兜底档（4.5d.1: framework 已删）"
  if ! grep -q "unknown 档" "$CLAUDE_TMPL"; then
    _fail "CLAUDE.md.tmpl 工程结构约束 placeholder 应说明 unknown 档行为"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_schema_exists
test_derive_script_exists
test_both_templates_derived
test_templates_have_auto_generated_marker
test_prototype_template_has_depth_prose
test_system_template_has_depth_prose
test_custom_template_has_pm_fill_skeleton
test_check_mode_passes_for_synced
test_check_mode_detects_drift
test_invalid_schema_rejected
test_claude_tmpl_has_placeholder
test_claude_tmpl_documents_unknown_branch

report_results "structure-schema"
