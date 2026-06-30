#!/usr/bin/env bash
# test-lark-sync-skill.sh
#
# 防回归：/pmai-lark-sync 必须保持为同步方向分流入口，而不是退化成默认覆盖发布。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/lark-sync/SKILL.md"
REF_DIR="$REPO_ROOT/skills/lark-sync/references"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
README="$REPO_ROOT/README.md"
PUBLISH_SKILL="$REPO_ROOT/skills/publish-to-lark/SKILL.md"

test_skill_exists_and_frontmatter() {
  start_test "lark-sync skill 存在且 frontmatter 正确"
  assert_file_exists "$SKILL" "skills/lark-sync/SKILL.md should exist" || return
  assert_file_contains "$SKILL" "name: pmai-lark-sync" "frontmatter should expose pmai-lark-sync" || return
  pass_test
}

test_mode_routing_is_present() {
  start_test "lark-sync 包含四种同步模式"
  assert_file_contains "$SKILL" "精细修改飞书" "should include fine edit mode" || return
  assert_file_contains "$SKILL" "整篇覆盖" "should include overwrite mode" || return
  assert_file_contains "$SKILL" "飞书 -> 本地回拉最终版" "should include pull-from-lark mode" || return
  assert_file_contains "$SKILL" "只 diff，不修改" "should include diff-only mode" || return
  pass_test
}

test_safety_rules_are_locked() {
  start_test "lark-sync 锁定安全规则"
  assert_file_contains "$SKILL" "不能默认 overwrite" "should ban default overwrite" || return
  assert_file_contains "$SKILL" "每次写飞书后必须 fetch 回读" "should require fetch verification after writes" || return
  assert_file_contains "$SKILL" "不能从原型反推规格" "should ban deriving spec from prototype" || return
  assert_file_contains "$SKILL" "lark_revision_id" "should track lark revision" || return
  assert_file_contains "$SKILL" "lark_synced_at" "should track sync timestamp" || return
  pass_test
}

test_references_exist() {
  start_test "lark-sync references 全部存在"
  for f in intent-routing.md fine-edit-to-lark.md pull-from-lark.md diff-only.md verification.md; do
    assert_file_exists "$REF_DIR/$f" "reference $f should exist" || return
  done
  pass_test
}

test_no_machine_bound_paths() {
  start_test "lark-sync 不含机器绑定路径"
  if grep -R "/Users/" "$REPO_ROOT/skills/lark-sync" >/tmp/lark_sync_paths.$$ 2>&1; then
    _fail "lark-sync should not hardcode /Users paths: $(cat /tmp/lark_sync_paths.$$)"
    rm -f /tmp/lark_sync_paths.$$
    return
  fi
  rm -f /tmp/lark_sync_paths.$$
  pass_test
}

test_framework_exposure_docs_updated() {
  start_test "doctor / README / publish-to-lark 已接入 lark-sync"
  assert_file_contains "$DOCTOR" "lark-sync" "doctor EXPECTED_SKILLS should include lark-sync" || return
  assert_file_contains "$README" "/pmai-lark-sync" "README should list /pmai-lark-sync" || return
  assert_file_contains "$PUBLISH_SKILL" "/pmai-lark-sync" "publish-to-lark should point ambiguous sync to lark-sync" || return
  pass_test
}

test_skill_exists_and_frontmatter
test_mode_routing_is_present
test_safety_rules_are_locked
test_references_exist
test_no_machine_bound_paths
test_framework_exposure_docs_updated

report_results "lark-sync-skill"
