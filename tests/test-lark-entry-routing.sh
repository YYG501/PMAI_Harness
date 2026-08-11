#!/usr/bin/env bash
# Stable contracts for the three PM-facing Lark intents.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBLISH="$REPO_ROOT/skills/publish-to-lark/SKILL.md"
SYNC="$REPO_ROOT/skills/sync-from-lark/SKILL.md"
REVIEW="$REPO_ROOT/skills/lark-review/SKILL.md"
WRITEBACK="$REPO_ROOT/skills/_shared/lark-writeback.md"
VERIFY="$REPO_ROOT/skills/_shared/lark-document-verification.md"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
CLAUDE_TEMPLATE="$REPO_ROOT/templates/CLAUDE.md.tmpl"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"

test_public_entries_match_pm_intent() {
  start_test "Lark entries: public names match direction and judgment"
  assert_file_contains "$PUBLISH" "name: pmai-publish-to-lark" "publisher frontmatter should stay stable" || return
  assert_file_contains "$SYNC" "name: pmai-sync-from-lark" "pull entry should expose its direction" || return
  assert_file_contains "$REVIEW" "name: pmai-lark-review" "review frontmatter should stay stable" || return
  if [ -e "$REPO_ROOT/skills/lark-sync" ]; then
    _fail "the ambiguous four-mode lark-sync router should be retired"
    return
  fi
  pass_test
}

test_publish_owns_every_local_to_lark_strategy() {
  start_test "Lark entries: publish owns create, fine update, and explicit overwrite"
  assert_file_contains "$PUBLISH" "首次创建、精细更新和整篇覆盖是内部执行策略" \
    "publish should own all local-to-Lark strategies" || return
  assert_file_contains "$PUBLISH" "已有文档的“发布 / 更新飞书”默认保留原生内容" \
    "existing documents should default to fine update" || return
  assert_file_contains "$PUBLISH" "只有用户明确说.*覆盖.*才允许整篇覆盖" \
    "overwrite should require explicit intent" || return
  assert_file_contains "$PUBLISH" "skills/_shared/lark-writeback.md" \
    "publish should use the internal writeback contract" || return
  assert_file_contains "$PUBLISH" "/pmai-sync-from-lark" \
    "publish should route inbound mechanical sync to the directional entry" || return
  assert_file_contains "$PUBLISH" "/pmai-lark-review" \
    "publish should route remote divergence to review" || return
  pass_test
}

test_sync_from_lark_is_mechanical_and_inbound_only() {
  start_test "Lark entries: sync-from-lark is mechanical and inbound only"
  assert_file_contains "$SYNC" "以飞书为准、不需要判断" \
    "mechanical pull must require explicit source authority" || return
  assert_file_contains "$SYNC" "不猜真相源、不判断产品影响" \
    "mechanical pull must not become a semantic review" || return
  assert_file_contains "$SYNC" '把本地文档发布或更新到飞书：用 `/pmai-publish-to-lark`' \
    "outbound publication must route to publish" || return
  assert_file_contains "$SYNC" '默认进入 `/pmai-lark-review`' \
    "ambiguous remote edits should route to review" || return
  assert_file_contains "$SYNC" "active build" \
    "mechanical pull should stop on an active build" || return
  pass_test
}

test_review_uses_internal_writeback_directly() {
  start_test "Lark entries: review uses shared writeback without public-skill chaining"
  assert_file_contains "$REVIEW" "skills/_shared/lark-writeback.md" \
    "review should read the shared writeback contract" || return
  assert_file_contains "$REVIEW" '不要调用 `/pmai-publish-to-lark` 或其它公开 Skill' \
    "review should not chain through another public entry" || return
  if grep -Fq -- '/pmai-lark-sync' "$REVIEW"; then
    _fail "review still calls the retired lark-sync public entry"
    return
  fi
  assert_file_contains "$WRITEBACK" "两个公开入口不得为了复用执行步骤而互相调用" \
    "shared writeback must remain an internal capability" || return
  assert_file_contains "$WRITEBACK" '--content -' \
    "writeback should send content through stdin" || return
  assert_file_contains "$WRITEBACK" "revision 冲突时立即停止" \
    "writeback should fail closed on concurrent changes" || return
  assert_file_contains "$VERIFY" "任何写飞书动作后都必须重新 fetch" \
    "writeback must verify the remote result" || return
  pass_test
}

test_sources_and_host_catalog_are_updated() {
  start_test "Lark entries: source assets and host catalog use the new names"
  for file in \
    "$REPO_ROOT/skills/sync-from-lark/references/pull-from-lark.md" \
    "$REPO_ROOT/skills/sync-from-lark/references/diff-only.md" \
    "$WRITEBACK" "$VERIFY"; do
    assert_file_exists "$file" "missing Lark contract: $file" || return
  done
  assert_file_contains "$DOCTOR" "sync-from-lark" \
    "doctor should include the directional sync entry" || return
  assert_file_contains "$CLAUDE_TEMPLATE" "/pmai-publish-to-lark" \
    "consumer charter should explain outbound publication" || return
  assert_file_contains "$CLAUDE_TEMPLATE" "/pmai-sync-from-lark" \
    "consumer charter should explain mechanical inbound sync" || return
  assert_file_contains "$AGENTS_TEMPLATE" "飞书入口按方向和判断责任固定" \
    "consumer agent entry should preserve the three-way responsibility split" || return
  pass_test
}

test_no_machine_bound_paths() {
  start_test "Lark entries: new assets contain no machine-bound paths"
  if grep -R "/Users/" \
    "$REPO_ROOT/skills/publish-to-lark" \
    "$REPO_ROOT/skills/sync-from-lark" \
    "$WRITEBACK" "$VERIFY" >/tmp/lark_entry_paths.$$ 2>&1; then
    _fail "Lark assets should not hardcode /Users paths: $(cat /tmp/lark_entry_paths.$$)"
    rm -f /tmp/lark_entry_paths.$$
    return
  fi
  rm -f /tmp/lark_entry_paths.$$
  pass_test
}

test_public_entries_match_pm_intent
test_publish_owns_every_local_to_lark_strategy
test_sync_from_lark_is_mechanical_and_inbound_only
test_review_uses_internal_writeback_directly
test_sources_and_host_catalog_are_updated
test_no_machine_bound_paths

report_results "lark-entry-routing"
