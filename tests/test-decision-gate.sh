#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GATE="$FRAMEWORK_ROOT/scripts/decision-gate.py"
BUILD_CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
CONTEXT_PACK="$FRAMEWORK_ROOT/scripts/context-pack.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"
HOOK="$FRAMEWORK_ROOT/hooks/decision-gate-guard.cjs"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-decision-gate.XXXXXX")
  MODULE="$T/docs/modules/access"
  TARGET="prototype/src/access"
  mkdir -p "$MODULE" "$T/$TARGET" "$T/.pm-workflow"
  write_equivalent_product_baseline "$T"
  printf '# Rules\n' > "$T/PRODUCT-RULES.md"
  printf '# Design\n' > "$T/DESIGN.md"
  printf '# Todo\n' > "$T/TODO.md"
  printf '# Modules\n' > "$T/docs/modules/INDEX.md"
  printf '# Discussion\n' > "$MODULE/discussion.md"
  printf '# Decisions\n' > "$MODULE/decisions.md"
  printf '# Access spec\n' > "$MODULE/spec.md"
  printf 'export const access = true\n' > "$T/$TARGET/index.ts"
  printf '.pm-workflow/context/\n' > "$T/.gitignore"
  git -C "$T" init -q -b main
  git -C "$T" config user.email "test@example.com"
  git -C "$T" config user.name "PMAI Test"
  python3 "$PROJECT_DEFINITION" write "$T" \
    --source docs/modules/access/spec.md \
    --type prototype --root prototype --entrypoint prototype \
    --language typescript --runtime node --framework react --package-manager pnpm \
    >/dev/null
  git -C "$T" add -A
  git -C "$T" commit -q -m baseline
  python3 "$BUILD_CONTRACT" designing "$MODULE" >/dev/null
}

teardown_fixture() {
  rm -rf "$T"
}

open_gate() {
  local summary="$1" message="$2" session="$3"
  python3 "$GATE" open "$MODULE" \
    --kind product-model --summary "$summary" --message "$message" \
    --option '1=采用方案一' --option '2=采用方案二' \
    --allow-free-text --session-id "$session"
}

open_project_gate() {
  local summary="$1" message="$2" session="$3"
  python3 "$GATE" open-project "$T" \
    --kind one-way-door --summary "$summary" --message "$message" \
    --option '1=保留旧结果' --option '2=回到当前工作' \
    --session-id "$session"
}

observe_answer() {
  local message="$1" session="$2" message_id="$3"
  python3 "$GATE" observe --repo-root "$T" --message "$message" \
    --session-id "$session" --message-id "$message_id"
}

json_field() {
  python3 -c 'import json,sys; value=json.load(sys.stdin); print(value[sys.argv[1]])' "$1"
}

test_answer_is_bound_once_across_compaction() {
  start_test "decision gate: 已消费旧答复不能在压缩后复用于建议的新问题"
  setup_fixture

  local opened observed gate_id event_id checkpoint pack approved
  opened=$(open_gate "旧构建结果怎么处理" "请选择旧构建结果的处理方式" "session-1")
  gate_id=$(printf '%s' "$opened" | json_field gate_id)
  observed=$(observe_answer "1" "session-1" "message-old-1")
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer "$MODULE" --gate-id "$gate_id" --event-id "$event_id" >/dev/null
  python3 "$GATE" consume "$MODULE" --gate-id "$gate_id" --decision-id D31 >/dev/null
  printf '\n## D31 保留旧构建结果\n\n- 结论：保留并继续。\n' >> "$MODULE/decisions.md"
  git -C "$T" add -- docs/modules/access/decisions.md docs/modules/access/.work-meta.json

  if ! python3 "$GATE" check-staged --repo-root "$T" >/dev/null 2>&1; then
    _fail "fresh consumed receipt should authorize its own staged decision"
    teardown_fixture
    return
  fi
  git -C "$T" commit -q -m "approve old build handling"
  checkpoint=$(git -C "$T" rev-parse HEAD)
  pack="$T/.pm-workflow/context/access.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$pack" >/dev/null
  approved=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$pack")
  python3 "$BUILD_CONTRACT" ready "$MODULE" \
    --approved-source-hash "$approved" --checkpoint-commit "$checkpoint" \
    --context-pack "$pack" --target-path "$TARGET" >/dev/null
  git -C "$T" add -- docs/modules/access/.work-meta.json
  git -C "$T" commit -q -m "mark ready"

  # Compression summary may suggest another question, but summaries have no
  # command path that can create/open/answer/consume a gate. Returning to design
  # starts a fresh authorization baseline and leaves the old answer consumed.
  python3 "$BUILD_CONTRACT" designing "$MODULE" >/dev/null
  if python3 "$GATE" answer "$MODULE" --gate-id "$gate_id" --event-id "$event_id" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "one answer event must not be reusable after it was consumed"
  elif python3 "$GATE" guard-authority-write "$MODULE" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "a summary-only suggested question must not authorize decision writes"
  elif ! grep -q '没有唯一、尚未 checkpoint' /tmp/decision-gate.err.$$; then
    _fail "missing fresh-answer guidance should be explicit"
    cat /tmp/decision-gate.err.$$ >&2
  else
    pass_test
  fi

  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_project_route_answer_cannot_authorize_later_design_question() {
  start_test "decision gate: Proposal/阶段路由答复消费后不能授权后续 Design 问题"
  setup_fixture

  local opened gate_id observed event_id
  opened=$(open_project_gate "旧构建如何收口" "请选择旧构建的处理方式" "project-session")
  gate_id=$(printf '%s' "$opened" | json_field gate_id)
  observed=$(observe_answer "1" "project-session" "route-message-1")
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer-project "$T" --gate-id "$gate_id" --event-id "$event_id" >/dev/null
  python3 "$GATE" consume-project "$T" --gate-id "$gate_id" --artifact route:proposal >/dev/null

  opened=$(open_gate "租户角色来源" "邀请时角色从哪里来" "project-session")
  local module_gate
  module_gate=$(printf '%s' "$opened" | json_field gate_id)
  if python3 "$GATE" answer "$MODULE" --gate-id "$module_gate" --event-id "$event_id" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "a consumed project route answer must not answer a later module gate"
  elif ! grep -q '不是在本题 pending 时捕获' /tmp/decision-gate.err.$$; then
    _fail "cross-scope answer rejection should name the binding problem"
  elif python3 "$GATE" guard-project-write "$T" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "a consumed route gate must not authorize a later Proposal write"
  elif ! grep -q '没有唯一、尚未消费' /tmp/decision-gate.err.$$; then
    _fail "later Proposal writes should require a newly answered project gate"
  else
    pass_test
  fi

  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_project_proposal_commit_requires_matching_artifact() {
  start_test "decision gate: Proposal 原子提交需要对应项目动作收据"
  setup_fixture
  mkdir -p "$T/docs/proposals"
  printf '# Proposal draft\n' > "$T/docs/proposals/demo-v1.md"
  printf '# Proposal index\n' > "$T/docs/proposals/INDEX.md"
  git -C "$T" add -- docs/proposals/demo-v1.md docs/proposals/INDEX.md

  local opened gate_id observed event_id
  opened=$(open_project_gate "生成 Proposal 草案" "是否生成完整 Proposal 草案" "proposal-session")
  gate_id=$(printf '%s' "$opened" | json_field gate_id)
  observed=$(observe_answer "1" "proposal-session" "proposal-answer-1")
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer-project "$T" --gate-id "$gate_id" --event-id "$event_id" >/dev/null
  python3 "$GATE" consume-project "$T" --gate-id "$gate_id" --artifact proposal:draft >/dev/null
  if ! python3 "$GATE" check-staged --repo-root "$T" >/dev/null 2>&1; then
    _fail "proposal draft files should accept a consumed proposal:draft receipt"
    teardown_fixture
    return
  fi

  printf '\n同步基线\n' >> "$T/PRODUCT.md"
  git -C "$T" add -- PRODUCT.md
  if python3 "$GATE" check-staged --repo-root "$T" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "PRODUCT.md must reject a draft-only receipt"
  elif ! grep -q 'proposal:accept' /tmp/decision-gate.err.$$; then
    _fail "PRODUCT.md rejection should require proposal:accept"
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_staged_and_ready_reject_missing_receipt() {
  start_test "decision gate: 新产品决定缺收据时 pre-commit 与 ready 都失败"
  setup_fixture
  printf '\n## D33 系统预置角色\n\n- 结论：直接采用。\n' >> "$MODULE/decisions.md"
  git -C "$T" add -- docs/modules/access/decisions.md docs/modules/access/.work-meta.json
  if python3 "$GATE" check-staged --repo-root "$T" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "staged D33 without a receipt must fail"
    teardown_fixture
    return
  fi
  if ! (cd "$T" && PMAI_HOME="$FRAMEWORK_ROOT" bash "$FRAMEWORK_ROOT/scripts/install-hooks.sh") \
    >/dev/null 2>&1; then
    _fail "fixture pre-commit hook should install"
    teardown_fixture
    return
  elif PMAI_HOME="$FRAMEWORK_ROOT" git -C "$T" commit -q -m "unauthorized D33" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "installed pre-commit must reject D33 without a receipt"
    teardown_fixture
    return
  fi
  git -C "$T" commit -q --no-verify -m "forge D33"
  local checkpoint pack approved
  checkpoint=$(git -C "$T" rev-parse HEAD)
  pack="$T/.pm-workflow/context/access.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$pack" >/dev/null
  approved=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$pack")
  if python3 "$BUILD_CONTRACT" ready "$MODULE" \
    --approved-source-hash "$approved" --checkpoint-commit "$checkpoint" \
    --context-pack "$pack" --target-path "$TARGET" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "ready must independently reject missing PM authorization"
  elif ! grep -q 'D33' /tmp/decision-gate.err.$$; then
    _fail "ready rejection should identify the unauthorized decision"
    cat /tmp/decision-gate.err.$$ >&2
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_pending_gate_is_unique_and_answer_event_stays_local() {
  start_test "decision gate: 一个 work 只允许一题 pending，答复事件只属于当时问题"
  setup_fixture
  local opened gate_id observed event_id
  opened=$(open_gate "角色来源" "角色由谁维护" "session-2")
  gate_id=$(printf '%s' "$opened" | json_field gate_id)
  if open_gate "第二题" "不应同时展示" "session-2" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "a work must not open a second unresolved gate"
    teardown_fixture
    return
  fi
  observed=$(observe_answer "1" "session-2" "message-role-1")
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer "$MODULE" --gate-id "$gate_id" --event-id "$event_id" >/dev/null
  python3 "$GATE" cancel "$MODULE" --gate-id "$gate_id" --reason "PM 改谈其它事项" >/dev/null
  opened=$(open_gate "角色范围" "角色能否跨租户" "session-2")
  gate_id=$(printf '%s' "$opened" | json_field gate_id)
  if python3 "$GATE" answer "$MODULE" --gate-id "$gate_id" --event-id "$event_id" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "an answer candidate from an older gate must not bind to a later gate"
  elif ! grep -q '不是在本题 pending 时捕获' /tmp/decision-gate.err.$$; then
    _fail "cross-gate answer rejection should name the binding problem"
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_equal_text_answers_without_host_message_ids_stay_distinct() {
  start_test "decision gate: 同一会话连续回复相同编号仍是两条独立用户消息"
  setup_fixture
  local opened gate_id observed first_event second_event
  opened=$(open_gate "角色来源" "角色由谁维护" "session-repeat")
  gate_id=$(printf '%s' "$opened" | json_field gate_id)
  observed=$(python3 "$GATE" observe --repo-root "$T" --message "1" \
    --session-id "session-repeat" --transcript-path "$T/session.jsonl")
  first_event=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer "$MODULE" --gate-id "$gate_id" --event-id "$first_event" >/dev/null
  python3 "$GATE" cancel "$MODULE" --gate-id "$gate_id" --reason "测试下一题" >/dev/null

  opened=$(open_gate "角色范围" "角色能否跨租户" "session-repeat")
  gate_id=$(printf '%s' "$opened" | json_field gate_id)
  observed=$(python3 "$GATE" observe --repo-root "$T" --message "1" \
    --session-id "session-repeat" --transcript-path "$T/session.jsonl")
  second_event=$(printf '%s' "$observed" | json_field event_id)
  if [ "$first_event" = "$second_event" ]; then
    _fail "equal answer text without host message IDs must still create distinct events"
  elif ! python3 "$GATE" answer "$MODULE" --gate-id "$gate_id" --event-id "$second_event" >/dev/null; then
    _fail "the second observed user message should answer the second displayed gate"
  else
    pass_test
  fi
  teardown_fixture
}

test_hook_observes_prompt_and_blocks_unanswered_writes() {
  start_test "decision gate hook: UserPromptSubmit 捕获答复，PreToolUse 阻止未答决定写入"
  setup_fixture
  open_gate "角色来源" "角色由谁维护" "hook-session" >/dev/null
  local prompt_payload prompt_out write_payload write_out
  prompt_payload=$(printf '{"hook_event_name":"UserPromptSubmit","cwd":"%s","session_id":"hook-session","message_id":"hook-message-1","prompt":"1"}' "$T")
  prompt_out=$(cd "$T" && printf '%s' "$prompt_payload" | node "$HOOK")
  write_payload=$(printf '{"hook_event_name":"PreToolUse","cwd":"%s","tool_name":"Write","tool_input":{"file_path":"%s/docs/modules/access/decisions.md","content":"forged"}}' "$T" "$T")
  write_out=$(cd "$T" && printf '%s' "$write_payload" | node "$HOOK")
  if [[ "$prompt_out" != *'answer_event_id'* ]] \
    || [[ "$write_out" != *'permissionDecision":"deny'* ]]; then
    _fail "hook should capture the current answer event and deny writes before answer selection"
    echo "$prompt_out" >&2
    echo "$write_out" >&2
  elif ! python3 - "$MODULE/.work-meta.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
item = meta["decision_gates"]["items"][-1]
assert item["status"] == "pending"
assert len(item["answer_candidates"]) == 1
assert item["answer_candidates"][0]["message_id"] == "hook-message-1"
PY
  then
    _fail "hook observation must stay on the displayed pending gate"
  else
    pass_test
  fi
  teardown_fixture
}

test_multiple_pending_gates_are_not_guessed() {
  start_test "decision gate: 多个 pending 候选时不按时间或顺序猜题"
  setup_fixture
  local second="$T/docs/modules/billing"
  mkdir -p "$second"
  printf '# Discussion\n' > "$second/discussion.md"
  printf '# Decisions\n' > "$second/decisions.md"
  printf '# Billing spec\n' > "$second/spec.md"
  python3 "$BUILD_CONTRACT" designing "$second" >/dev/null
  open_gate "角色来源" "角色由谁维护" "shared-session" >/dev/null
  python3 "$GATE" open "$second" \
    --kind product-model --summary "计费来源" --message "计费由谁维护" \
    --option '1=方案一' --option '2=方案二' --session-id "shared-session" >/dev/null
  local result
  result=$(python3 "$GATE" observe --repo-root "$T" --message "1" \
    --session-id "shared-session" --message-id "ambiguous-message")
  if [[ "$result" != *'"status": "ambiguous"'* ]]; then
    _fail "ambiguous pending gates must not capture the message"
    echo "$result" >&2
  elif ! python3 - "$MODULE/.work-meta.json" "$second/.work-meta.json" <<'PY'
import json, sys
for path in sys.argv[1:]:
    item = json.load(open(path))["decision_gates"]["items"][-1]
    assert item["status"] == "pending"
    assert item["answer_candidates"] == []
PY
  then
    _fail "ambiguous message must leave every gate unchanged"
  else
    pass_test
  fi
  teardown_fixture
}

test_old_ready_without_receipts_is_unverifiable() {
  start_test "decision gate: 旧未开工 ready 缺授权收据时退回 Design"
  setup_fixture
  local checkpoint pack approved
  checkpoint=$(git -C "$T" rev-parse HEAD)
  pack="$T/.pm-workflow/context/access.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$pack" >/dev/null
  approved=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$pack")
  python3 - "$MODULE/.work-meta.json" "$approved" "$checkpoint" "$TARGET" <<'PY'
import json, sys
path, approved, checkpoint, target = sys.argv[1:]
meta = json.load(open(path))
meta.pop("decision_gates", None)
meta.update({
    "lifecycle_state": "ready_to_build",
    "approved_source_hash": approved,
    "design_checkpoint_commit": checkpoint,
    "approved_target": {"paths": [target]},
    "design_revision": 1,
})
json.dump(meta, open(path, "w"), ensure_ascii=False, indent=2)
PY
  if python3 "$BUILD_CONTRACT" validate-ready "$MODULE" --context-pack "$pack" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "old ready without receipts must not remain buildable"
  elif ! grep -q 'authorization_unverifiable' /tmp/decision-gate.err.$$; then
    _fail "legacy ready should receive a machine-readable authorization reason"
    cat /tmp/decision-gate.err.$$ >&2
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_answer_is_bound_once_across_compaction
test_project_route_answer_cannot_authorize_later_design_question
test_project_proposal_commit_requires_matching_artifact
test_staged_and_ready_reject_missing_receipt
test_pending_gate_is_unique_and_answer_event_stays_local
test_equal_text_answers_without_host_message_ids_stay_distinct
test_hook_observes_prompt_and_blocks_unanswered_writes
test_multiple_pending_gates_are_not_guessed
test_old_ready_without_receipts_is_unverifiable
report_results "decision-gate"
