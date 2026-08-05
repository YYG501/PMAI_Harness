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
    })
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
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
  assert_file_contains "$SKILL" "B / L / R.*只读证据" "skill should keep source versions read-only" || return
  assert_file_contains "$SKILL" "只有已 seal 的 T" "skill should make T the only writable target" || return
  assert_file_contains "$SKILL" "整批只走一条主执行路径" "mixed batch should use one lifecycle" || return
  assert_file_contains "$SKILL" "未验证完成前不解决评论" "comments must remain open before verification" || return
  assert_file_contains "$SKILL" "全量评论围栏" "checkpoint should bind all comments, including solved comments" || return
  assert_file_contains "$SKILL" "is_solved=false.*is_solved=true" "full comment fence must query both solved states explicitly" || return
  assert_file_contains "$SKILL" "lark-review.py.*complete-comment" "comments should be completed through the controlled command" || return
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
  assert_file_contains "$README" "/pmai-lark-review" "README should list lark-review" || return
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
  if rg -n '/Users/' "$REPO_ROOT/skills/lark-review" "$COLLECTOR" >/dev/null; then
    _fail "lark-review assets must not contain machine-bound paths"
    return
  fi
  assert_file_contains "$SKILL" "没有.*--force" "skill should explicitly forbid force bypasses" || return
  if rg -n 'add_argument\([^)]*--force' "$COLLECTOR" >/dev/null; then
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
assert set(data["artifacts"]) == {"baseline.md", "local.md", "remote.md"}
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
    item.update(decision="no_spec_change", authority="existing_spec", reason="无需改规格")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
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
        item.update(decision="applied", authority="pm_confirmed", reason="按评论补充完成条件")
    else:
        item.update(decision="no_spec_change", authority="existing_spec", reason="无需额外修改")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
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
    )
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

test_incompatible_baseline_starts_target_from_local() {
  start_test "lark-review: B 与本地发布源格式不兼容时 T 从 L 初始化"
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
  python3 - "$work/out/review.json" "$work/out/apply-plan.json" <<'PY'
import json, sys
manifest = json.load(open(sys.argv[1], encoding="utf-8"))
plan = json.load(open(sys.argv[2], encoding="utf-8"))
assert manifest["body"]["common_ancestor_compatible"] is False
assert plan["required_items"]["body"][0]["kind"] == "ancestor_incompatible"
assert plan["required_items"]["body"][0]["decision"] == "pending"
PY
  if [ "$?" -ne 0 ] || ! grep -Fq 'Old [rule]' "$work/out/target.md" \
    || grep -q '^New rule$' "$work/out/target.md"; then
    _fail "incompatible ancestor should keep L as draft target"
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
        decision="no_spec_change", authority="existing_spec", reason="无需改规格"
    )
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  local out rc
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '使用了不支持的归位决定'; then
    _fail "incompatible ancestor must not permit whole-document remote-wins: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["body"][0].update(
    decision="local", authority="existing_spec", reason="保留当前本地规格"
)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q '缺少 PM.*明确确认'; then
    _fail "incompatible ancestor must not select L without PM confirmation: rc=$rc out=$out"
    return
  fi
  python3 - "$work/out/resolutions.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["body"][0].update(
    decision="local", authority="pm_confirmed", reason="PM 明确确认保留本地规格"
)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(python3 "$COLLECTOR" reconcile --manifest "$work/out/review.json" \
    --resolutions "$work/out/resolutions.json" --seal 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "PM-confirmed local target should seal: rc=$rc out=$out"
    return
  fi
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
test_checkpoint_failure_can_recollect_solved_comment
test_checkpoint_preserves_deferred_comments
test_same_second_comment_uses_create_time_and_id_boundary
test_baseline_refresh_is_atomic
test_reconcile_seals_target_before_apply
test_applied_comment_requires_changed_lifecycle_target
test_apply_rejects_local_change_after_collect
test_apply_rejects_remote_or_comment_change
test_already_applied_rechecks_local_cas
test_manual_merge_requires_compiled_target
test_incompatible_baseline_starts_target_from_local
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
