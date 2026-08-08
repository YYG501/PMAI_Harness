#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/lark-review/SKILL.md"
ROUTING="$REPO_ROOT/skills/lark-review/references/review-routing.md"
COLLECTOR="$REPO_ROOT/scripts/lark-review.py"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
README="$REPO_ROOT/README.md"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"
CLAUDE_TEMPLATE="$REPO_ROOT/templates/CLAUDE.md.tmpl"
PUBLISH_SKILL="$REPO_ROOT/skills/publish-to-lark/SKILL.md"
SYNC_SKILL="$REPO_ROOT/skills/lark-sync/SKILL.md"
DESIGN_SKILL="$REPO_ROOT/skills/design/SKILL.md"
BUILD_SKILL="$REPO_ROOT/skills/build/SKILL.md"
QUICK_FIX_SKILL="$REPO_ROOT/skills/quick-fix/SKILL.md"
SPEC_SKILL="$REPO_ROOT/skills/spec-writing/SKILL.md"
HANDOFF="$REPO_ROOT/skills/lark-review/references/lifecycle-handoff.md"

BASE=$(mktemp -d /tmp/pmai-lark-review-test-XXXXXX)
SHIM="$BASE/bin"
mkdir -p "$SHIM"
cp "$SCRIPT_DIR/helpers/fake-lark-review-cli.sh" "$SHIM/lark-cli"
chmod +x "$SHIM/lark-cli"
export PATH="$SHIM:$PATH"
export PYTHONPYCACHEPREFIX="$BASE/pycache"

cleanup() {
  rm -rf "$BASE"
}
trap cleanup EXIT

make_review_doc() {
  local path="$1"
  local body='# Spec

Old rule
'
  local hash
  hash=$(printf '%s' "$body" | PYTHONPATH="$REPO_ROOT/scripts" python3 -c 'import sys; from _lib.lark_adapter import markdown_body_hash; print(markdown_body_hash(sys.stdin.read()))')
  {
    echo '---'
    echo 'lark_doc_id: docR'
    echo 'lark_doc_url: https://example.feishu.cn/docx/docR'
    echo 'lark_published_revision_id: 7'
    echo "lark_published_source_hash: $hash"
    echo 'lark_reviewed_comment_at: 150'
    echo '---'
    echo
    printf '%s' "$body"
  } > "$path"
}

complete_decision_routing() {
  python3 - "$1" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["decision_routing"]:
    item.update(
        outcome="not_required",
        target_path="",
        decision_id="",
        supersedes=[],
        summary="",
        reason="测试项不改变稳定产品规则",
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

seal_simple_review() {
  local work="$1"
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null || return 1
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    item.update({
        "decision": "no_spec_change",
        "authority": "existing_spec",
        "reason": "测试中确认评论不需要额外修改规格",
        "result_text": "Updated and verified",
    })
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json" || return 1
  python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal >/dev/null
}

seal_controlled_review() {
  local work="$1"
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null || return 1
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    if item["comment_id"] == "c1":
        item.update({
            "decision": "no_spec_change",
            "authority": "existing_spec",
            "reason": "测试中确认评论不需要额外修改规格",
            "result_text": "Updated and verified",
        })
    else:
        item.update({
            "decision": "deferred",
            "authority": "pm_confirmed",
            "reason": "测试中保留为未解决评论",
        })
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json" || return 1
  python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal >/dev/null
}

prepare_controlled_review() {
  local work="$1"
  mkdir -p "$work/out" "$work/remote-state"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null || return 1
  seal_controlled_review "$work" || return 1
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null || return 1
  refresh_review_baseline "$work" || return 1
  FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" >/dev/null || return 1
}

prepare_batch_review() {
  local work="$1"
  mkdir -p "$work/out" "$work/remote-state"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null || return 1
  seal_simple_review "$work" || return 1
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null || return 1
  refresh_review_baseline "$work" || return 1
  FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" >/dev/null || return 1
}

complete_controlled_c1() {
  local work="$1"
  FAKE_REVIEW_SYNCED_REMOTE=1 \
  FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
  FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 \
      --result-text 'Updated and verified'
}

refresh_review_baseline() {
  local work="$1"
  local revision="${2:-10}"
  local target_hash
  target_hash=$(python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["target"]["body_sha256"])' \
    "$work/out/apply-plan.json") || return 1
  FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_SYNCED_REVISION="$revision" \
    python3 "$COLLECTOR" baseline "$work/spec.md" \
      --revision-id "$revision" \
      --expected-source-hash "$target_hash" >/dev/null
}

test_skill_contract() {
  start_test "lark-review: Skill 暴露、基线和分流合同完整"
  assert_file_contains "$SKILL" "name: pmai-lark-review" "frontmatter should expose pmai-lark-review" || return
  assert_file_contains "$SKILL" "lark-review.py.*collect" "skill should call deterministic collector" || return
  assert_file_contains "$SKILL" "lark-review.py.*reconcile" "skill should require deterministic reconciliation" || return
  assert_file_contains "$SKILL" "lark-review.py.*apply" "skill should require guarded target apply" || return
  assert_file_contains "$SKILL" "remote_native_snapshot" "review target must be based on the native remote snapshot" || return
  assert_file_contains "$SKILL" "remote-coverage.json" "review must expose remote content/format coverage" || return
  assert_file_contains "$SKILL" "内容与格式：.*核对" "final receipt must report content and format preservation as a PM-readable outcome" || return
  assert_file_contains "$SKILL" "lark-review.py.*verify-sync" "review must verify native format after writeback" || return
  assert_file_contains "$SKILL" "10–15 分钟" "review must define a machine-time performance target" || return
  assert_file_contains "$SKILL" "产品规则变化写.*decisions.md.*措辞和格式变化不得" "decision recording must be selective" || return
  assert_file_contains "$SKILL" "decision_routing" "decision archival routing must be explicit before seal" || return
  assert_file_contains "$SKILL" "B / L / R.*只读证据" "skill should keep source versions read-only" || return
  assert_file_contains "$SKILL" "只有已 seal 的 T" "skill should make T the only writable target" || return
  assert_file_contains "$SKILL" "整批只走一条主执行路径" "mixed batch should use one lifecycle" || return
  assert_file_contains "$SKILL" "未验证完成前不解决评论" "comments must remain open before verification" || return
  assert_file_contains "$SKILL" "全量评论围栏" "checkpoint should bind all comments, including solved comments" || return
  assert_file_contains "$SKILL" "is_solved=false.*is_solved=true" "full comment fence must query both solved states explicitly" || return
  assert_file_contains "$SKILL" "lark-review.py.*complete-comments" "new batches should complete comments through one controlled batch command" || return
  assert_file_contains "$SKILL" "comments\[\].result_text" "comment result text should be sealed before batch completion" || return
  assert_file_contains "$SKILL" "批次开始.*全部写入结束.*稳定全量评论围栏" "batch completion should use stable boundary scans" || return
  assert_file_contains "$SKILL" "checkpoint.*复用.*不重复下载 full XML" "checkpoint should reuse revision-bound native verification" || return
  assert_file_contains "$SKILL" "comment-actions.json" "checkpoint should consume controlled comment receipts" || return
  assert_file_contains "$SKILL" "lark-review.py.*reopen" "checkpoint recovery should reopen system-solved batch comments" || return
  assert_file_contains "$SKILL" "不接受自由填写.*reply.*author.*solver" "comment recovery must not trust caller-supplied identities" || return
  assert_file_contains "$SKILL" "\.pm-workflow/context/lark-review" "review batches should survive across turns outside Git" || return
  assert_file_contains "$SKILL" "连续两轮.*围栏" "full comment scans should require consecutive stable fences" || return
  assert_file_contains "$SKILL" "决定.*归位.*同步.*飞书" "authority promotion must precede remote synchronization" || return
  assert_file_contains "$SKILL" "checkpoint 不替代" "checkpoint should keep lifecycle evidence in downstream gates" || return
  assert_file_contains "$HANDOFF" "apply 成功前不得改写任何权威产品状态" "authority writes must wait for apply" || return
  assert_file_contains "$ROUTING" "revision 不能可靠证明.*PM 已认可" "remote revision must not impersonate PM approval" || return
  assert_file_contains "$ROUTING" "只问一次是否全部认可" "unattributed body edits should use one batch confirmation" || return
  assert_file_contains "$ROUTING" "产品变化" "routing should distinguish product changes" || return
  assert_file_contains "$DOCTOR" "lark-review" "doctor should expose lark-review" || return
  assert_file_contains "$AGENTS_TEMPLATE" "/pmai-lark-review" "consumer AGENTS should route lark review" || return
  assert_file_contains "$CLAUDE_TEMPLATE" "/pmai-lark-review" "consumer CLAUDE should list lark-review" || return
  assert_file_contains "$PUBLISH_SKILL" "lark_published_revision_id" "publisher should record review revision" || return
  assert_file_contains "$SYNC_SKILL" "/pmai-lark-review" "plain sync should route review intent" || return
  assert_file_contains "$HANDOFF" "apply 前：只收敛候选决定并编译 T" "handoff should apply T before implementation" || return
  assert_file_contains "$SKILL" "lark_published_source_hash.*T" "checkpoint should verify the final published target" || return
  assert_file_contains "$DESIGN_SKILL" "lifecycle-handoff.md" "design should honor review handoff" || return
  assert_file_contains "$BUILD_SKILL" "lifecycle-handoff.md" "build should honor review handoff" || return
  assert_file_contains "$QUICK_FIX_SKILL" "lifecycle-handoff.md" "quick-fix should honor review handoff" || return
  assert_file_contains "$SPEC_SKILL" "lifecycle-handoff.md" "spec-writing should output review target" || return
  if grep -R -n '/Users/' "$REPO_ROOT/skills/lark-review" "$COLLECTOR" >/dev/null; then
    _fail "lark-review assets must not contain machine-bound paths"
    return
  fi
  assert_file_contains "$SKILL" "没有.*--force" "skill should explicitly forbid force bypasses" || return
  if grep -E -n 'add_argument\([^)]*--force' "$COLLECTOR" >/dev/null; then
    _fail "lark-review CLI must not expose a force option"
    return
  fi
  pass_test
}

test_collect_rejects_changes_during_comment_collection() {
  start_test "lark-review: 评论采集期间本地或飞书变化时不生成混杂批次"
  local remote_work="$BASE/collect-remote-race"
  mkdir -p "$remote_work/out" "$remote_work/state"
  make_review_doc "$remote_work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_REMOTE_CHANGES_AFTER_FETCH=1 \
    FAKE_REVIEW_STATE_DIR="$remote_work/state" \
    python3 "$COLLECTOR" collect "$remote_work/spec.md" \
    --output-dir "$remote_work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书正文在评论采集期间变化' \
    || [ -e "$remote_work/out/review.json" ]; then
    _fail "remote collect race should fail before manifest: rc=$rc out=$out"
    return
  fi

  local local_work="$BASE/collect-local-race"
  mkdir -p "$local_work/out"
  make_review_doc "$local_work/spec.md"
  out=$(FAKE_REVIEW_MUTATE_LOCAL_PATH="$local_work/spec.md" \
    python3 "$COLLECTOR" collect "$local_work/spec.md" \
    --output-dir "$local_work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '本地 markdown 在评论采集期间变化' \
    || [ -e "$local_work/out/review.json" ] \
    || ! grep -q '^Concurrent local edit$' "$local_work/spec.md"; then
    _fail "local collect race should fail without overwriting: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_collects_three_way_body_and_paginated_comments() {
  start_test "lark-review: 三方正文、评论分页、回复分页与 block 定位"
  local work="$BASE/full"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  export FAKE_LARK_LOG="$work/lark.log"
  local out
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  local rc=$?
  unset FAKE_LARK_LOG
  if [ "$rc" -ne 0 ]; then
    _fail "collector failed: $out"
    return
  fi
  python3 - "$work/out/review.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["body"]["status"] == "remote_only", data["body"]
assert data["body"]["baseline_status"] == "revision"
assert data["body"]["common_ancestor_compatible"] is True
assert len(data["body"]["remote_source_hash"]) == 64
assert data["batch_id"]
assert set(data["artifacts"]) == {
    "baseline.md", "local.md", "remote.md", "remote-native.json"
}
assert data["body"]["target_base"] == "remote_native_snapshot"
assert data["performance"]["document_full_fetches"] == 1
assert data["performance"]["document_snapshot_pairs"] == 1
assert data["performance"]["document_revision_fence_fetches"] == 1
assert data["performance"]["document_fetch_api_calls"] == 4
assert data["document"]["published_revision_id"] == 7
assert data["document"]["current_revision_id"] == 9
comments = data["comments"]
assert comments["count"] == 2, comments
assert comments["interaction_count"] == 3, comments
assert comments["reply_count"] == 1, comments
assert comments["new_or_updated_count"] == 2, comments
first, second = comments["items"]
assert first["location"]["accuracy"] == "relation_exact", first
assert first["location"]["block_id"] == "b-rule", first
assert first["replies"][0]["text"] == "Use new rule", first
assert second["location"]["accuracy"] == "quote_ambiguous", second
assert len(second["replies"]) == 2, second
assert second["replies"][1]["text"] == "Second reply", second
PY
  if [ "$?" -ne 0 ]; then
    _fail "review.json assertions failed"
    return
  fi
  if ! grep -q -- '^-Old rule' "$work/out/remote-vs-baseline.diff" \
    || ! grep -q -- '^+New rule' "$work/out/remote-vs-baseline.diff"; then
    _fail "remote diff missing expected change"
    return
  fi
  if ! grep -q '"is_solved":false' "$work/lark.log" \
    || ! grep -q '"is_solved":true' "$work/lark.log" \
    || ! grep -q '"need_relation":true' "$work/lark.log" \
    || ! grep -q 'comments-next' "$work/lark.log" \
    || ! grep -q 'replies-next' "$work/lark.log"; then
    _fail "pagination or unresolved/relation params missing: $(cat "$work/lark.log")"
    return
  fi
  pass_test
}

test_checkpoint_is_separate_and_preserves_body() {
  start_test "lark-review: 完成后 checkpoint 单独写入且保留正文/基线"
  local work="$BASE/checkpoint"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }
  FAKE_REVIEW_SYNCED_REMOTE=1 \
  FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
  FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-04T12:00:00+08:00' >/dev/null
  if ! grep -q '^lark_reviewed_revision_id: 10$' "$work/spec.md" \
    || ! grep -q '^lark_reviewed_comment_at: 270$' "$work/spec.md" \
    || ! grep -q '^lark_reviewed_comment_ids: \["comment:c1"\]$' "$work/spec.md" \
    || ! grep -q '^lark_reviewed_at: 2026-08-04T12:00:00+08:00$' "$work/spec.md" \
    || ! grep -q '^lark_published_revision_id: 10$' "$work/spec.md" \
    || ! grep -q '^New rule$' "$work/spec.md"; then
    _fail "checkpoint fields/body incorrect: $(cat "$work/spec.md")"
    return
  fi
  pass_test
}

test_checkpoint_requires_published_target_and_resolved_comments() {
  start_test "lark-review: checkpoint 前必须已发布 T 且完成本批评论"
  local work="$BASE/checkpoint-gates"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_controlled_review "$work" || { _fail "failed to seal review batch"; return; }
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '发布基线尚未指向本批目标 T' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject an unpublished T: rc=$rc out=$out"
    return
  fi

  refresh_review_baseline "$work" || { _fail "failed to refresh baseline"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'comment-actions.json' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject comments without controlled receipts: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_remote_mismatch_and_new_unresolved_comment() {
  start_test "lark-review: checkpoint 阻断远端版本漂移和受控回执后的新回复"
  local work="$BASE/checkpoint-races"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_SYNCED_REVISION=11 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书当前 revision 与本地发布基线不一致'; then
    _fail "checkpoint should reject remote revision drift: rc=$rc out=$out"
    return
  fi

  : > "$work/remote-state/pm-after-result-c1"
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论围栏与完成回执不一致' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject a reply after the controlled receipt: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_reopened_out_of_batch_comment() {
  start_test "lark-review: PM 手工回复和解决不能冒充受控完成或被 reopen"
  local work="$BASE/checkpoint-manual-solve"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  : > "$work/remote-state/manual-reply-c1"
  : > "$work/remote-state/solved-c1"

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'comment-actions.json' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject PM manual completion: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" reopen "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'comment-actions.json' \
    || [ -e "$work/remote-state/reopened-c1" ]; then
    _fail "reopen should reject PM manual completion: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_solved_out_of_batch_comment() {
  start_test "lark-review: 评论写入和最终回读失败保留可恢复中间回执"
  local work="$BASE/comment-action-partial"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_PATCH_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'solve_requested'; then
    _fail "patch failure should leave solve_requested: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["actions"][0]["status"] == "solve_requested"
assert data["actions"][0]["reply"]["reply_id"] == "r-result-c1"
PY
  then
    _fail "partial action receipt was not recoverable"
    return
  fi
  complete_controlled_c1 "$work" >/dev/null || {
    _fail "complete-comment failed to recover solve_requested"; return;
  }

  local read_work="$BASE/comment-action-read-failure"
  prepare_controlled_review "$read_work" || { _fail "failed to prepare read failure review"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_FINAL_READ_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$read_work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$read_work/out/review.json" \
      --plan "$read_work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '回读失败'; then
    _fail "final read failure should fail closed: rc=$rc out=$out"
    return
  fi
  complete_controlled_c1 "$read_work" >/dev/null || {
    _fail "complete-comment failed to recover after final read failure"; return;
  }
  if ! python3 - "$read_work/out/comment-actions.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["actions"][0]["status"] == "completed"
PY
  then
    _fail "final read recovery did not complete the receipt"
    return
  fi
  pass_test
}

test_checkpoint_binds_system_result_reply() {
  start_test "lark-review: complete-comment 生成绑定批次和远端身份的受控回执"
  local work="$BASE/checkpoint-result-reply"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }

  local out rc
  out=$(python3 "$COLLECTOR" checkpoint "$work/spec.md" \
    --manifest "$work/out/review.json" --plan "$work/out/apply-plan.json" \
    --result-reply 'c1=r-result' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'unrecognized arguments'; then
    _fail "checkpoint must remove caller-supplied reply IDs: rc=$rc out=$out"
    return
  fi
  out=$(python3 "$COLLECTOR" reopen "$work/spec.md" \
    --manifest "$work/out/review.json" --plan "$work/out/apply-plan.json" \
    --comment-id c1 --solver-author ou-shared 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'unrecognized arguments'; then
    _fail "reopen must remove caller-supplied solver identity: rc=$rc out=$out"
    return
  fi
  out=$(complete_controlled_c1 "$work" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "completed"'; then
    _fail "controlled completion failed: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" "$work/out/apply-plan.json" <<'PY'
import json, sys
actions = json.load(open(sys.argv[1], encoding="utf-8"))
plan = json.load(open(sys.argv[2], encoding="utf-8"))
action = actions["actions"][0]
assert actions["batch_id"] == plan["batch_id"]
assert actions["plan"]["ready_token"] == plan["ready_token"]
assert action["status"] == "completed"
assert action["reply"]["reply_id"] == "r-result-c1"
assert action["reply"]["user_id"] == "ou-shared"
assert action["solver_user_id"] == "ou-shared"
assert action["solved_time"] == 270
PY
  then
    _fail "controlled receipt is not bound to batch/plan/reply/solver"
    return
  fi
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-04T12:40:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^lark_reviewed_revision_id: 10$' "$work/spec.md"; then
    _fail "checkpoint should accept the controlled receipt: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_complete_comment_accepts_sparse_create_response() {
  start_test "lark-review: 创建回复响应缺正文时绑定实际发送文本 hash"
  local work="$BASE/sparse-reply-create"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_REPLY_CREATE_NO_CONTENT=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 \
      --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "completed"'; then
    _fail "sparse reply create response should complete: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import hashlib, json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
reply = data["actions"][0]["reply"]
assert reply["reply_id"] == "r-result-c1"
assert reply["text_sha256"] == hashlib.sha256(b"Updated and verified").hexdigest()
PY
  then
    _fail "sparse create response did not preserve the sent result hash"
    return
  fi
  pass_test
}

test_complete_comments_batches_full_scans_and_checkpoint_reuses_verification() {
  start_test "lark-review: 整批评论只在首尾全量扫描且 checkpoint 复用格式验收"
  local work="$BASE/comment-batch"
  prepare_batch_review "$work" || { _fail "failed to prepare batch review"; return; }
  : > "$work/lark.log"

  local out rc
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"execution_mode": "batch"'; then
    _fail "batch completion failed: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["execution_mode"] == "batch"
assert [item["comment_id"] for item in value["actions"]] == ["c1", "c2"]
assert all(item["status"] == "completed" for item in value["actions"])
assert all(item["solved_time"] is None for item in value["actions"])
assert all(item["solve_evidence_mode"] == "write_ack_and_stable_readback" for item in value["actions"])
perf = value["performance"]
assert perf["attempt_count"] == 1, perf
assert perf["comment_full_scans"] == 4, perf
assert perf["comment_list_api_calls"] == 10, perf
assert perf["reply_write_api_calls"] == 2, perf
assert perf["solve_write_api_calls"] == 2, perf
PY
  then
    _fail "batch receipt or performance counters are incorrect"
    return
  fi
  local list_calls
  list_calls=$(grep -c 'file.comments list' "$work/lark.log")
  if [ "$list_calls" -ne 10 ]; then
    _fail "batch should use 10 list page calls for two stable boundary scans, got $list_calls"
    return
  fi

  : > "$work/lark.log"
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-07T12:00:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || grep -q -- '--doc-format xml' "$work/lark.log"; then
    _fail "checkpoint should reuse native verification without full XML: rc=$rc out=$out"
    return
  fi
  if [ "$(grep -c 'file.comments list' "$work/lark.log")" -ne 4 ] \
    || [ "$(grep -c 'docs +fetch' "$work/lark.log")" -ne 1 ]; then
    _fail "checkpoint should use one stable comment scan and one markdown fence: $(cat "$work/lark.log")"
    return
  fi
  pass_test
}

test_complete_comments_recovers_partial_batch_without_duplicate_replies() {
  start_test "lark-review: 整批评论中断后按 journal 恢复且不重复回复"
  local work="$BASE/comment-batch-recovery"
  prepare_batch_review "$work" || { _fail "failed to prepare batch review"; return; }
  : > "$work/lark.log"

  local out rc
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_PATCH_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'journal 已保留'; then
    _fail "batch patch failure should retain journal: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "batch recovery failed: rc=$rc out=$out"
    return
  fi
  if [ "$(grep -c 'file.comment.replys create' "$work/lark.log")" -ne 2 ]; then
    _fail "batch recovery duplicated a result reply: $(cat "$work/lark.log")"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["performance"]["attempt_count"] == 2
assert all(item["status"] == "completed" for item in value["actions"])
PY
  then
    _fail "recovered batch receipt is incomplete"
    return
  fi
  pass_test
}

test_batch_final_read_failure_can_recover_and_reopen() {
  start_test "lark-review: 批量 solve 已确认但最终回读中断后仍可受控 reopen"
  local work="$BASE/comment-batch-reopen-recovery"
  prepare_batch_review "$work" || { _fail "failed to prepare batch review"; return; }
  : > "$work/lark.log"

  local out rc
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_FINAL_READ_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comments \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'journal 已保留'; then
    _fail "batch final read failure should retain journal: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert all(item["status"] == "solve_requested" for item in value["actions"])
assert all(item["solve_write_ack_sha256"] for item in value["actions"])
PY
  then
    _fail "failed batch did not retain solve write acknowledgements"
    return
  fi

  : > "$work/remote-state/pm-after-result-c1"
  out=$(FAKE_LARK_LOG="$work/lark.log" \
    FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" reopen "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id 'c1' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "reopened"'; then
    _fail "solve_requested batch action could not recover and reopen: rc=$rc out=$out"
    return
  fi
  if ! python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
actions = {item["comment_id"]: item for item in value["actions"]}
assert actions["c1"]["status"] == "reopened"
assert actions["c2"]["status"] == "completed"
assert actions["c1"]["solved_time"] is None
assert actions["c2"]["solved_time"] is None
assert actions["c1"]["solve_evidence_mode"] == "write_ack_and_stable_readback"
assert actions["c2"]["solve_evidence_mode"] == "write_ack_and_stable_readback"
PY
  then
    _fail "reopen recovery did not persist controlled completion evidence"
    return
  fi
  if [ "$(grep -c 'file.comment.replys create' "$work/lark.log")" -ne 2 ]; then
    _fail "reopen recovery duplicated result replies: $(cat "$work/lark.log")"
    return
  fi
  pass_test
}

test_checkpoint_failure_can_recollect_solved_comment() {
  start_test "lark-review: 结果回复竞态失败后先受控 reopen 再重新采集"
  local work="$BASE/checkpoint-solved-recovery"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }
  mkdir -p "$work/recovery"
  : > "$work/remote-state/pm-after-result-c1"

  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论围栏与完成回执不一致' \
    || grep -q '^lark_reviewed_revision_id:' "$work/spec.md"; then
    _fail "checkpoint should reject PM feedback racing the result reply: rc=$rc out=$out"
    return
  fi

  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" reopen "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id 'c1' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"status": "reopened"' \
    || [ ! -e "$work/remote-state/reopened-c1" ]; then
    _fail "failed to reopen the system-solved batch comment: rc=$rc out=$out"
    return
  fi

  FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" collect "$work/spec.md" \
      --output-dir "$work/recovery" --include-solved >/dev/null || {
        _fail "failed to recollect solved comments after checkpoint rejection"
        return
      }
  python3 "$COLLECTOR" reconcile --manifest "$work/recovery/review.json" >/dev/null
  if ! python3 - "$work/recovery/review.json" "$work/recovery/resolutions.json" <<'PY'
import json, sys
review = json.load(open(sys.argv[1], encoding="utf-8"))
resolutions = json.load(open(sys.argv[2], encoding="utf-8"))
comment = next(item for item in review["comments"]["items"] if item["comment_id"] == "c1")
assert comment["is_solved"] is False
assert any(reply["text"] == "Actually use B" for reply in comment["replies"])
assert "c1" in {item["comment_id"] for item in resolutions["comments"]}
PY
  then
    _fail "solved comment or PM reply missing from recovery batch"
    return
  fi
  pass_test
}

test_checkpoint_preserves_deferred_comments() {
  start_test "lark-review: deferred 评论必须保持未解决才可 checkpoint"
  local work="$BASE/checkpoint-deferred"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  complete_controlled_c1 "$work" >/dev/null || { _fail "failed to complete c1"; return; }

  local out rc
  : > "$work/remote-state/solved-c2"
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论围栏与完成回执不一致'; then
    _fail "checkpoint should reject a solved deferred comment: rc=$rc out=$out"
    return
  fi

  local clean="$BASE/checkpoint-deferred-open"
  prepare_controlled_review "$clean" || { _fail "failed to prepare open deferred review"; return; }
  complete_controlled_c1 "$clean" >/dev/null || { _fail "failed to complete clean c1"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_STATE_DIR="$clean/remote-state" \
    python3 "$COLLECTOR" checkpoint "$clean/spec.md" \
      --manifest "$clean/out/review.json" \
      --plan "$clean/out/apply-plan.json" \
      --reviewed-at '2026-08-04T12:30:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^lark_reviewed_revision_id: 10$' "$clean/spec.md"; then
    _fail "checkpoint should accept an unchanged open deferred comment: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_same_second_comment_uses_create_time_and_id_boundary() {
  start_test "lark-review: 同秒新评论用 create_time + ID 水位识别"
  local work="$BASE/same-second"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  FAKE_REVIEW_CREATE_ONLY=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 - "$work/out/review.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["comments"]["new_or_updated_count"] == 1, data["comments"]
assert data["comments"]["max_update_time"] == 150
assert data["comments"]["max_update_ids"] == [
    "comment:c-same-second", "reply:r-same-second"
]
PY
  if [ "$?" -ne 0 ]; then
    _fail "same-second cursor assertions failed"
    return
  fi
  pass_test
}

test_baseline_refresh_is_atomic() {
  start_test "lark-review: 精细同步后原子刷新 revision 与正文 hash"
  local work="$BASE/baseline"
  mkdir -p "$work"
  make_review_doc "$work/spec.md"
  local old_hash new_hash expected_hash
  old_hash=$(sed -n 's/^lark_published_source_hash: //p' "$work/spec.md")
  printf '\nLocal final.\n' >> "$work/spec.md"
  expected_hash=$(PYTHONPATH="$REPO_ROOT/scripts" python3 - "$work/spec.md" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import markdown_body_hash, parse_frontmatter
_, body = parse_frontmatter(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(markdown_body_hash(body))
PY
)
  python3 "$COLLECTOR" baseline "$work/spec.md" --revision-id 9 \
    --expected-source-hash "$expected_hash" >/dev/null
  new_hash=$(sed -n 's/^lark_published_source_hash: //p' "$work/spec.md")
  if ! grep -q '^lark_published_revision_id: 9$' "$work/spec.md" \
    || [ "$old_hash" = "$new_hash" ] || [ "$new_hash" != "$expected_hash" ]; then
    _fail "baseline refresh incorrect: old=$old_hash new=$new_hash expected=$expected_hash"
    return
  fi
  pass_test
}

test_reconcile_seals_target_before_apply() {
  start_test "lark-review: B/L/R 先归位为独立 T，seal 后才允许写规格"
  local work="$BASE/reconcile"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/apply-plan.json" "$work/out/resolutions.json" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
resolutions = json.load(open(sys.argv[2], encoding="utf-8"))
assert plan["state"] == "draft", plan
assert plan["unresolved_count"] == 2, plan
assert len(resolutions["body"]) == 1
assert resolutions["body"][0]["decision"] == "remote"
assert all(item["decision"] == "pending" for item in resolutions["comments"])
PY
  if [ "$?" -ne 0 ] || ! grep -q '^New rule$' "$work/out/target.md" \
    || ! grep -q '^Old rule$' "$work/spec.md"; then
    _fail "draft target or source isolation incorrect"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    item.update(decision="no_spec_change", authority="existing_spec", reason="无需改规格", result_text="Updated and verified")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal >/dev/null
  python3 "$COLLECTOR" apply "$work/spec.md" --plan "$work/out/apply-plan.json" >/dev/null
  local second
  second=$(python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  local stale rc
  stale=$(FAKE_REVIEW_REMOTE_CHANGED=1 python3 "$COLLECTOR" apply \
    "$work/spec.md" --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if ! grep -q '^New rule$' "$work/spec.md" \
    || ! echo "$second" | grep -q 'already_applied' \
    || [ "$rc" -eq 0 ] \
    || ! echo "$stale" | grep -q '飞书正文 revision' \
    || ! grep -q '^lark_doc_id: docR$' "$work/spec.md"; then
    _fail "sealed target apply/idempotency fence failed: second=$second stale=$stale"
    return
  fi
  pass_test
}

test_decision_routing_is_explicit_and_selective() {
  start_test "lark-review: 每个飞书变化显式路由 decision 且只沉淀产品规则"
  local work="$BASE/decision-routing"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    item.update(
        decision="no_spec_change",
        authority="existing_spec",
        reason="不改变规格规则",
        result_text="Updated and verified",
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '尚未完成 decision 归档路由'; then
    _fail "pending decision routing must block seal: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["decision_routing"]:
    if item["source_type"] == "body":
        item.update(
            outcome="supersede",
            target_path="docs/modules/example/decisions.md",
            decision_id="D-NEW-RULE",
            supersedes=["D-OLD-RULE"],
            summary="飞书确认采用新业务规则",
            reason="正文修改改变稳定业务规则",
        )
    else:
        item.update(
            outcome="not_required",
            target_path="",
            decision_id="",
            supersedes=[],
            summary="",
            reason="评论仅解释现有规则",
        )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "valid selective decision routing should seal: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/apply-plan.json" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
assert plan["decision_write_count"] == 1
route = next(item for item in plan["decision_routing"] if item["outcome"] == "supersede")
assert route["decision_id"] == "D-NEW-RULE"
assert route["supersedes"] == ["D-OLD-RULE"]
PY
  [ "$?" -eq 0 ] || { _fail "decision routing missing from ready plan"; return; }
  pass_test
}

test_applied_comment_requires_changed_lifecycle_target() {
  start_test "lark-review: applied 评论必须实际编译进独立 T"
  local work="$BASE/applied-comment"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
for item in data["comments"]:
    if item["comment_id"] == "c1":
        item.update(decision="applied", authority="pm_confirmed", reason="按评论补充完成条件", result_text="Updated and verified")
    else:
        item.update(decision="no_spec_change", authority="existing_spec", reason="无需额外修改", result_text="Updated and verified")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '评论标记 applied 时'; then
    _fail "applied comment should reject an unchanged reconciled T: rc=$rc out=$out"
    return
  fi

  printf '\nApplied completion rule.\n' >> "$work/out/target.md"
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["target"] = {
    "mode": "lifecycle_compiled",
    "authority": "pm_confirmed",
    "reason": "按已确认评论重新编译规格",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^Applied completion rule\.$' "$work/out/target.md"; then
    _fail "changed lifecycle-compiled T should seal: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_apply_rejects_local_change_after_collect() {
  start_test "lark-review: apply 前本地正文变化时零写入"
  local work="$BASE/local-race"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  printf '\nConcurrent local edit\n' >> "$work/spec.md"
  local out rc
  out=$(python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '本地规格正文已在 collect 后变化' \
    || ! grep -q '^Concurrent local edit$' "$work/spec.md"; then
    _fail "local CAS should reject without overwriting: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_apply_rejects_remote_or_comment_change() {
  start_test "lark-review: apply 前飞书正文或评论变化时零写入"
  local work="$BASE/remote-race"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  local out rc
  out=$(FAKE_REVIEW_REMOTE_CHANGED=1 python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书正文 revision' \
    || ! grep -q '^Old rule$' "$work/spec.md"; then
    _fail "remote revision fence should reject: rc=$rc out=$out"
    return
  fi
  out=$(FAKE_REVIEW_COMMENT_CHANGED=1 python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '飞书评论或回复' \
    || ! grep -q '^Old rule$' "$work/spec.md"; then
    _fail "comment fence should reject: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_already_applied_rechecks_local_cas() {
  start_test "lark-review: already_applied 返回前仍复核本地正文"
  local work="$BASE/already-applied-local-race"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null
  local out rc
  out=$(FAKE_REVIEW_MUTATE_LOCAL_PATH="$work/spec.md" \
    python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '本地规格在远端复核期间变化' \
    || ! grep -q '^Concurrent local edit$' "$work/spec.md"; then
    _fail "already_applied local CAS should fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_manual_merge_requires_compiled_target() {
  start_test "lark-review: 双边冲突标记 merged 时必须真正编译 T"
  local work="$BASE/manual-merge"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  sed -i.bak 's/^Old rule$/Local rule/' "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
assert data["body"][0]["decision"] == "pending", data["body"]
data["body"][0].update(
    decision="merged",
    authority="pm_confirmed",
    reason="PM 确认合并本地与飞书口径",
)
for item in data["comments"]:
    item.update(
        decision="no_spec_change",
        authority="existing_spec",
        reason="无需额外修改规格",
        result_text="Updated and verified",
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -Eq '冲突标记|target.md 与机械归位结果不一致'; then
    _fail "merged should not silently select local; rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
resolutions_path = sys.argv[1]
data = json.load(open(resolutions_path, encoding="utf-8"))
data["target"] = {
    "mode": "lifecycle_compiled",
    "authority": "pm_confirmed",
    "reason": "按已确认决定编译合并后的规格",
}
with open(resolutions_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  cp "$work/out/local.md" "$work/out/target.md"
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不能退化为完整 L 或完整 R'; then
    _fail "manual merged target must not equal full L: rc=$rc out=$out"
    return
  fi
  cp "$work/out/remote.md" "$work/out/target.md"
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不能退化为完整 L 或完整 R'; then
    _fail "manual merged target must not equal full R: rc=$rc out=$out"
    return
  fi
  printf '# Spec\n\nMerged rule\n' > "$work/out/target.md"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - \
    "$work/out/resolutions.json" "$work/out/remote.md" "$work/out/target.md" <<'PY'
import json, sys
from pathlib import Path
from _lib.lark_review_semantics import markdown_semantic_units

resolutions_path = Path(sys.argv[1])
remote_units = markdown_semantic_units(Path(sys.argv[2]).read_text(encoding="utf-8"))
target_units = markdown_semantic_units(Path(sys.argv[3]).read_text(encoding="utf-8"))
remote_rule = next(item for item in remote_units if item.text == "New rule")
target_rule = next(item for item in target_units if item.text == "Merged rule")
data = json.loads(resolutions_path.read_text(encoding="utf-8"))
data["remote_coverage"] = [{
    "remote_unit_id": remote_rule.unit_id,
    "disposition": "rewritten",
    "target_unit_ids": [target_rule.unit_id],
    "format_disposition": "preserved",
    "evidence": {
        "kind": "decision",
        "id": data["body"][0]["change_id"],
        "reason": "PM 已确认把双边规则合并为新口径",
    },
}]
resolutions_path.write_text(
    json.dumps(data, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^Merged rule$' "$work/out/target.md"; then
    _fail "compiled merged target should seal; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_incompatible_remote_only_starts_target_from_native_remote() {
  start_test "lark-review: remote-only 即使祖先格式不兼容也从飞书原生快照初始化 T"
  local work="$BASE/incompatible"
  mkdir -p "$work/out"
  local body='# Spec

Old [rule]
'
  local hash
  hash=$(printf '%s' "$body" | PYTHONPATH="$REPO_ROOT/scripts" python3 -c 'import sys; from _lib.lark_adapter import markdown_body_hash; print(markdown_body_hash(sys.stdin.read()))')
  {
    echo '---'
    echo 'lark_doc_id: docR'
    echo 'lark_doc_url: https://example.feishu.cn/docx/docR'
    echo 'lark_published_revision_id: 7'
    echo "lark_published_source_hash: $hash"
    echo '---'
    echo
    printf '%s' "$body"
  } > "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/review.json" "$work/out/apply-plan.json" "$work/out/remote-native.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
plan = json.load(open(sys.argv[2], encoding="utf-8"))
native = json.load(open(sys.argv[3], encoding="utf-8"))
assert manifest["body"]["common_ancestor_compatible"] is False
assert plan["required_items"]["body"][0]["kind"] == "ancestor_incompatible"
assert plan["target_base"] == "remote_native_snapshot"
assert plan["target_base_revision"] == 9
assert manifest["artifacts"]["remote-native.json"]["sha256"]
assert native["document"]["revision_id"] == 9
assert 'align="left"' in native["document"]["content"]
assert '<b>New rule</b>' in native["document"]["content"]
assert native["document"]["reference_map"]["doc:spec"] == "docR"
PY
  if [ "$?" -ne 0 ] || ! grep -q '^New rule$' "$work/out/target.md" \
    || grep -Fq 'Old [rule]' "$work/out/target.md"; then
    _fail "incompatible remote-only target must start from current remote"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["body"][0].update(
    decision="remote", authority="pm_confirmed", reason="PM 确认采用飞书正文"
)
for item in data["comments"]:
    item.update(
        decision="no_spec_change", authority="existing_spec", reason="无需改规格",
        result_text="Updated and verified"
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^New rule$' "$work/out/target.md"; then
    _fail "PM-confirmed remote target should seal from R: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_unassigned_remote_rewrite_blocks_seal() {
  start_test "lark-review: R 到 T 的无依据改写阻止 seal"
  local work="$BASE/remote-coverage"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  sed -i.bak 's/^New rule$/Rewritten without evidence/' "$work/out/target.md"
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["target"].update(
    mode="lifecycle_compiled",
    authority="pm_confirmed",
    reason="测试远端覆盖门禁",
)
for item in data["comments"]:
    item.update(decision="no_spec_change", authority="existing_spec", reason="无需改规格", result_text="Updated and verified")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '远端语义.*未归位'; then
    _fail "unassigned remote rewrite must block seal: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/remote-coverage.json" <<'PY'
import json, sys
coverage = json.load(open(sys.argv[1], encoding="utf-8"))
assert coverage["summary"]["unassigned_count"] == 1, coverage
assert coverage["summary"]["remote_accounted_ratio"] < 1
assert coverage["summary"]["remote_format_accounted_ratio"] < 1
PY
  [ "$?" -eq 0 ] || { _fail "coverage ledger must expose the missing remote unit"; return; }
  pass_test
}

test_duplicate_remote_units_keep_independent_native_format_accounts() {
  start_test "lark-review: 同文重复段落的原生格式账本互不豁免"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - <<'PY'
from _lib.lark_review_semantics import (
    build_native_snapshot,
    build_remote_coverage,
    markdown_semantic_units,
)

remote = "# Spec\n\nRepeat\n\nRepeat\n"
target = "# Spec\n\nRepeat\n"
remote_repeats = [u for u in markdown_semantic_units(remote) if u.text == "Repeat"]
snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": '<?xml version="1.0" encoding="UTF-8"?><h1 id="b-title">Spec</h1><p id="b-repeat-1" align="left">Repeat</p><p id="b-repeat-2" align="right">Repeat</p>',
})
resolution = {
    "remote_unit_id": remote_repeats[1].unit_id,
    "disposition": "removed",
    "target_unit_ids": [],
    "format_disposition": "removed_with_content",
    "evidence": {"kind": "pm_exception", "id": "remove-second", "reason": "PM 删除第二段"},
}
coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[resolution],
    batch_id="batch",
    remote_revision_id=9,
)
native = {item["block_id"]: item for item in coverage["native_format_entries"]}
assert native["b-repeat-1"]["format_disposition"] == "preserved", native
assert native["b-repeat-2"]["format_disposition"] == "removed_with_content", native
assert coverage["summary"]["format_unassigned_count"] == 0

bad = {**resolution, "format_disposition": "intentional_change"}
bad_coverage = build_remote_coverage(
    remote,
    target,
    native_snapshot=snapshot,
    resolutions=[bad],
    batch_id="batch",
    remote_revision_id=9,
)
assert bad_coverage["summary"]["unassigned_count"] == 1
assert bad_coverage["summary"]["format_unassigned_count"] == 1

semantic_remote = "# Spec\n\nUse [policy](https://remote.example) with `account_id` and **Required**.\n"
semantic_target = "# Spec\n\nUse [policy](https://local.example) with `accountid` and Required.\n"
semantic_snapshot = build_native_snapshot({
    "document_id": "docR",
    "revision_id": 9,
    "content": '<h1 id="b-semantic-title">Spec</h1><p id="b-semantic"><a href="https://remote.example">policy</a><code>account_id</code><b>Required</b></p>',
})
semantic_coverage = build_remote_coverage(
    semantic_remote,
    semantic_target,
    native_snapshot=semantic_snapshot,
    resolutions=[],
    batch_id="batch-semantic",
    remote_revision_id=9,
)
assert semantic_coverage["summary"]["unassigned_count"] == 1, semantic_coverage
PY
  if [ "$?" -ne 0 ]; then
    _fail "duplicate native format accounting is not independent"
    return
  fi
  pass_test
}

test_comment_without_solved_time_can_checkpoint() {
  start_test "lark-review: 缺少 solved_time 时以写回执和稳定回读收口"
  local work="$BASE/comment-no-solved-time"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q 'write_ack_and_stable_readback'; then
    _fail "missing solved_time should use controlled readback evidence: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
action = json.load(open(sys.argv[1], encoding="utf-8"))["actions"][0]
assert action["status"] == "completed"
assert action["solved_time"] is None
assert action["solve_evidence_mode"] == "write_ack_and_stable_readback"
assert action["solve_write_ack_sha256"]
PY
  [ "$?" -eq 0 ] || { _fail "controlled receipt is incomplete"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" checkpoint "$work/spec.md" \
      --manifest "$work/out/review.json" --plan "$work/out/apply-plan.json" \
      --reviewed-at '2026-08-07T12:00:00+08:00' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! grep -q '^lark_reviewed_revision_id: 10$' "$work/spec.md"; then
    _fail "checkpoint should accept stable no-time receipt: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_verify_sync_preserves_native_format_and_resources() {
  start_test "lark-review: 精细写回后机器验证飞书原生格式和资源"
  local work="$BASE/verify-sync"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"format_coverage": 1.0'; then
    _fail "native format verification should pass: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/remote-verification.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
assert value["target_base"] == "remote_native_snapshot"
assert value["content_projection_match"] is True
assert value["remote_format_accounted_ratio"] == 1.0
assert value["preserved_native_block_count"] == 5
assert value["original_references_preserved"] is True
PY
  [ "$?" -eq 0 ] || { _fail "remote verification receipt is incomplete"; return; }
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 FAKE_REVIEW_FORMAT_LOSS=1 \
    python3 "$COLLECTOR" verify-sync \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -Eq '格式或资源未被保留|引用映射未被完整保留'; then
    _fail "format/resource loss must fail verification: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_structural_remote_change_requires_pm_preview() {
  start_test "lark-review: 结构性 R 到 T 改写强制 PM 预览"
  local work="$BASE/remote-preview"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  sed -i.bak 's/^# Spec$/# Updated spec/' "$work/out/target.md"
  PYTHONPATH="$REPO_ROOT/scripts" python3 - \
    "$work/out/resolutions.json" "$work/out/remote.md" "$work/out/target.md" <<'PY'
import json, sys
from pathlib import Path
from _lib.lark_review_semantics import markdown_semantic_units

path = Path(sys.argv[1])
remote = markdown_semantic_units(Path(sys.argv[2]).read_text(encoding="utf-8"))
target = markdown_semantic_units(Path(sys.argv[3]).read_text(encoding="utf-8"))
old_heading = next(item for item in remote if item.kind == "heading")
new_heading = next(item for item in target if item.kind == "heading")
data = json.loads(path.read_text(encoding="utf-8"))
data["target"] = {
    "mode": "lifecycle_compiled",
    "authority": "pm_confirmed",
    "reason": "按 PM 确认更新标题",
}
for item in data["comments"]:
    item.update(decision="no_spec_change", authority="existing_spec", reason="无需改规格", result_text="Updated and verified")
data["remote_coverage"] = [{
    "remote_unit_id": old_heading.unit_id,
    "disposition": "rewritten",
    "target_unit_ids": [new_heading.unit_id],
    "format_disposition": "preserved",
    "evidence": {
        "kind": "pm_exception",
        "id": "pm-heading-confirmation",
        "reason": "PM 确认标题改写但保留原样式",
    },
}]
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  complete_decision_routing "$work/out/resolutions.json"
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '强制预览阈值' \
    || ! grep -q 'remote-heading-' "$work/out/remote-preview.md"; then
    _fail "structural rewrite should stop for PM preview: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["preview"] = {
    "approved": True,
    "authority": "pm_confirmed",
    "reason": "PM 已查看结构改写预览并确认",
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q '"preview_required": true'; then
    _fail "PM-approved structural preview should seal: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_legacy_receipt_recovers_without_solved_time() {
  start_test "lark-review: v1 solve_requested 缺少 solved_time 时受控升级恢复"
  local work="$BASE/legacy-no-solved-time"
  prepare_controlled_review "$work" || { _fail "failed to prepare review"; return; }
  python3 - "$work/out/review.json" "$work/out/apply-plan.json" <<'PY'
import hashlib, json, sys
manifest_path, plan_path = sys.argv[1:]
manifest = json.load(open(manifest_path, encoding="utf-8"))
manifest["schema_version"] = 2
with open(manifest_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
plan = json.load(open(plan_path, encoding="utf-8"))
plan["schema_version"] = 2
plan["manifest"]["sha256"] = hashlib.sha256(open(manifest_path, "rb").read()).hexdigest()
plan.pop("ready_token", None)
encoded = json.dumps(plan, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
plan["ready_token"] = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
with open(plan_path, "w", encoding="utf-8") as handle:
    json.dump(plan, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  local out rc
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_FINAL_READ_FAIL=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'solve_requested'; then
    _fail "failed readback should leave a recoverable solve request: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["schema_version"] = 1
for action in data["actions"]:
    action.pop("solve_evidence_mode", None)
    action.pop("solve_write_ack_sha256", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(FAKE_REVIEW_SYNCED_REMOTE=1 \
    FAKE_REVIEW_CONTROLLED_ACTIONS=1 \
    FAKE_REVIEW_NO_SOLVED_TIME=1 \
    FAKE_REVIEW_STATE_DIR="$work/remote-state" \
    python3 "$COLLECTOR" complete-comment \
      --manifest "$work/out/review.json" \
      --plan "$work/out/apply-plan.json" \
      --comment-id c1 --result-text 'Updated and verified' 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q 'legacy_stable_readback'; then
    _fail "legacy no-time receipt should recover: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/comment-actions.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
action = data["actions"][0]
assert data["schema_version"] == 2
assert action["status"] == "completed"
assert action["solved_time"] is None
assert action["solve_evidence_mode"] == "legacy_stable_readback"
assert action["solve_write_ack_sha256"] is None
PY
  [ "$?" -eq 0 ] || { _fail "legacy receipt upgrade is incomplete"; return; }
  pass_test
}

test_review_requires_cli_with_versioned_docs_skills() {
  start_test "lark-review: 使用评论和 Markdown fetch 时要求专用 CLI 最低版本"
  local work="$BASE/old-cli"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_VERSION='lark-cli 1.0.48' python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '最低要求 1.0.49'; then
    _fail "old review CLI should fail closed: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_legacy_document_degrades_without_claiming_delta() {
  start_test "lark-review: 旧文档无发布基线时降级为 legacy"
  local work="$BASE/legacy"
  mkdir -p "$work/out"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_id: docR
---

# Spec

Old rule
MD
  local out
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  if [ "$?" -ne 0 ]; then
    _fail "legacy collection should succeed: $out"
    return
  fi
  local status
  status=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["body"]["status"])' "$work/out/review.json")
  if [ "$status" != "legacy_baseline" ]; then
    _fail "expected legacy_baseline, got $status"
    return
  fi
  pass_test
}

test_recorded_revision_failure_is_fail_closed() {
  start_test "lark-review: 已记录历史 revision 读取失败时阻断"
  local work="$BASE/fail-baseline"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_FAIL_BASELINE=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '不能安全识别正文增量'; then
    _fail "expected fail-closed baseline error; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_recorded_revision_response_must_match_requested_revision() {
  start_test "lark-review: 历史版本响应与请求不一致时阻断"
  local work="$BASE/wrong-baseline"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_WRONG_BASELINE=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '历史版本响应与请求不一致'; then
    _fail "expected mismatched baseline response to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_current_markdown_and_xml_must_share_revision() {
  start_test "lark-review: Markdown/XML revision 持续不一致时阻断"
  local work="$BASE/torn-pair"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_TORN_PAIR=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'revision 持续变化'; then
    _fail "expected torn current snapshot to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_doc_argument_must_match_frontmatter_url() {
  start_test "lark-review: --doc 与 frontmatter URL 身份冲突时阻断"
  local work="$BASE/doc-conflict"
  mkdir -p "$work/out"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_url: https://example.feishu.cn/docx/docOther
---

# Spec
MD
  local out rc
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --doc docR \
    --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'lark_doc_url'; then
    _fail "expected document identity conflict to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_collect_rejects_unbound_local_document() {
  start_test "lark-review: --doc 不能替代本地规格的持久身份绑定"
  local work="$BASE/unbound-local"
  mkdir -p "$work/out"
  cat > "$work/spec.md" <<'MD'
# Spec

Old rule
MD
  local out rc
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --doc docR \
    --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '缺少 lark_doc_id' \
    || [ -e "$work/out/review.json" ]; then
    _fail "unbound local document should fail during collect; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_checkpoint_rejects_rebound_document() {
  start_test "lark-review: collect 后文档重新绑定时拒绝旧 checkpoint"
  local work="$BASE/rebound"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  seal_simple_review "$work" || { _fail "failed to seal"; return; }
  python3 "$COLLECTOR" apply "$work/spec.md" \
    --plan "$work/out/apply-plan.json" >/dev/null
  sed -i.bak 's/^lark_doc_id: docR$/lark_doc_id: docOther/' "$work/spec.md"
  local out rc
  out=$(python3 "$COLLECTOR" checkpoint "$work/spec.md" \
    --manifest "$work/out/review.json" \
    --plan "$work/out/apply-plan.json" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '文档身份不匹配'; then
    _fail "expected rebound checkpoint to fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_baseline_accepts_url_only_and_rejects_revision_rollback() {
  start_test "lark-review: URL-only 文档可建基线且 revision 不得回退"
  local work="$BASE/url-baseline"
  mkdir -p "$work"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_url: https://example.feishu.cn/docx/docR
---

# Spec
MD
  local source_hash
  source_hash=$(PYTHONPATH="$REPO_ROOT/scripts" python3 - "$work/spec.md" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import markdown_body_hash, parse_frontmatter
_, body = parse_frontmatter(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(markdown_body_hash(body))
PY
)
  python3 "$COLLECTOR" baseline "$work/spec.md" --revision-id 9 \
    --expected-source-hash "$source_hash" >/dev/null
  if ! grep -q '^lark_doc_id: docR$' "$work/spec.md" \
    || ! grep -q '^lark_published_revision_id: 9$' "$work/spec.md"; then
    _fail "URL-only baseline 未补齐 canonical doc id: $(cat "$work/spec.md")"
    return
  fi
  local out rc
  out=$(python3 "$COLLECTOR" baseline "$work/spec.md" --revision-id 8 \
    --expected-source-hash "$source_hash" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '拒绝回退'; then
    _fail "baseline revision rollback should fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_legacy_doc_url_is_rejected_before_comment_collection() {
  start_test "lark-review: 旧版 /doc/ 与 /docs/ 链接在入口失败关闭"
  local work="$BASE/legacy-doc-url"
  mkdir -p "$work/out"
  cat > "$work/spec.md" <<'MD'
---
lark_doc_url: https://example.feishu.cn/doc/docLegacy
---

# Spec
MD
  local out rc
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '只支持飞书 Docx'; then
    _fail "legacy doc URL should fail before docx comment calls; rc=$rc out=$out"
    return
  fi
  sed -i.bak 's#/doc/docLegacy#/docs/docLegacy#' "$work/spec.md"
  out=$(python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '只支持飞书 Docx'; then
    _fail "legacy docs URL should fail before docx comment calls; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_invalid_pagination_is_fail_closed() {
  start_test "lark-review: has_more 无 token 时阻断"
  local work="$BASE/fail-page"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_BAD_PAGE=1 python3 "$COLLECTOR" collect \
    "$work/spec.md" --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '分页 token 缺失或重复'; then
    _fail "expected pagination failure; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_malformed_comment_pages_are_fail_closed() {
  start_test "lark-review: 畸形评论 envelope、item 和分页字段全部阻断"
  local cases=(
    'FAKE_REVIEW_DATA_NULL:data 不是对象'
    'FAKE_REVIEW_MALFORMED_ITEM:items 包含非对象条目'
    'FAKE_REVIEW_BAD_HAS_MORE:has_more 缺失或不是布尔值'
    'FAKE_REVIEW_BAD_PAGE_TOKEN_TYPE:page_token 不是字符串或 null'
  )
  local index=0 spec flag expected work out rc
  for spec in "${cases[@]}"; do
    index=$((index + 1))
    flag=${spec%%:*}
    expected=${spec#*:}
    work="$BASE/malformed-page-$index"
    mkdir -p "$work/out"
    make_review_doc "$work/spec.md"
    out=$(env "$flag=1" python3 "$COLLECTOR" collect \
      "$work/spec.md" --output-dir "$work/out" 2>&1)
    rc=$?
    if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q "$expected" \
      || [ -e "$work/out/review.json" ]; then
      _fail "$flag should fail closed before manifest: rc=$rc out=$out"
      return
    fi
  done
  pass_test
}

test_torn_solved_state_scan_retries_to_stability() {
  start_test "lark-review: 评论跨已解决状态查询切换时重试到连续稳定"
  local work="$BASE/torn-comment-state"
  mkdir -p "$work/out" "$work/state"
  make_review_doc "$work/spec.md"
  local out rc
  out=$(FAKE_REVIEW_TORN_COMMENT_SCAN_ONCE=1 \
    FAKE_REVIEW_STATE_DIR="$work/state" \
    python3 "$COLLECTOR" collect "$work/spec.md" \
      --output-dir "$work/out" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || [ ! -e "$work/out/review.json" ] \
    || [ ! -e "$work/state/torn-comment-scan-seen" ]; then
    _fail "transient solved-state overlap should retry: rc=$rc out=$out"
    return
  fi
  pass_test
}

test_resolutions_are_bound_to_review_batch() {
  start_test "lark-review: resolutions 账本不能跨批次复用"
  local work="$BASE/foreign-resolution-batch"
  mkdir -p "$work/out"
  make_review_doc "$work/spec.md"
  python3 "$COLLECTOR" collect "$work/spec.md" --output-dir "$work/out" >/dev/null
  python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" >/dev/null
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["batch_id"] = "different-review-batch"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  local out rc
  out=$(python3 "$COLLECTOR" reconcile \
    --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" \
    --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '批次不匹配'; then
    _fail "foreign resolutions batch should fail; rc=$rc out=$out"
    return
  fi
  pass_test
}

test_skill_contract
test_collects_three_way_body_and_paginated_comments
test_collect_rejects_changes_during_comment_collection
test_checkpoint_is_separate_and_preserves_body
test_checkpoint_requires_published_target_and_resolved_comments
test_checkpoint_rejects_remote_mismatch_and_new_unresolved_comment
test_checkpoint_rejects_reopened_out_of_batch_comment
test_checkpoint_rejects_solved_out_of_batch_comment
test_checkpoint_binds_system_result_reply
test_complete_comment_accepts_sparse_create_response
test_complete_comments_batches_full_scans_and_checkpoint_reuses_verification
test_complete_comments_recovers_partial_batch_without_duplicate_replies
test_batch_final_read_failure_can_recover_and_reopen
test_checkpoint_failure_can_recollect_solved_comment
test_checkpoint_preserves_deferred_comments
test_same_second_comment_uses_create_time_and_id_boundary
test_baseline_refresh_is_atomic
test_reconcile_seals_target_before_apply
test_decision_routing_is_explicit_and_selective
test_applied_comment_requires_changed_lifecycle_target
test_apply_rejects_local_change_after_collect
test_apply_rejects_remote_or_comment_change
test_already_applied_rechecks_local_cas
test_manual_merge_requires_compiled_target
test_incompatible_remote_only_starts_target_from_native_remote
test_unassigned_remote_rewrite_blocks_seal
test_duplicate_remote_units_keep_independent_native_format_accounts
test_comment_without_solved_time_can_checkpoint
test_verify_sync_preserves_native_format_and_resources
test_structural_remote_change_requires_pm_preview
test_legacy_receipt_recovers_without_solved_time
test_review_requires_cli_with_versioned_docs_skills
test_legacy_document_degrades_without_claiming_delta
test_recorded_revision_failure_is_fail_closed
test_recorded_revision_response_must_match_requested_revision
test_current_markdown_and_xml_must_share_revision
test_doc_argument_must_match_frontmatter_url
test_collect_rejects_unbound_local_document
test_checkpoint_rejects_rebound_document
test_baseline_accepts_url_only_and_rejects_revision_rollback
test_legacy_doc_url_is_rejected_before_comment_collection
test_invalid_pagination_is_fail_closed
test_malformed_comment_pages_are_fail_closed
test_torn_solved_state_scan_retries_to_stability
test_resolutions_are_bound_to_review_batch

report_results "lark-review"
