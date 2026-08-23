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

open_frontier_round() {
  python3 "$GATE" open-round "$MODULE" \
    --kind product-model --round-summary "通知范围与渠道" \
    --question '{"summary":"通知对象","message":"通知发给谁？","options":[{"id":"all","label":"所有成员"},{"id":"admins","label":"只有管理员"}],"allow_free_text":false}' \
    --question '{"summary":"通知渠道","message":"首版使用什么渠道？","options":[{"id":"in-app","label":"站内通知"},{"id":"email","label":"站内通知和邮件"}],"allow_free_text":false}' \
    --session-id "frontier-session"
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

test_frontier_round_binds_one_event_to_multiple_questions() {
  start_test "decision gate: Design frontier round 同轮多题共享答复事件但分别授权"
  setup_fixture

  local opened event_id observed
  opened=$(open_frontier_round)
  local gate_one gate_two
  gate_one=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["gate_id"])')
  gate_two=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[1]["gate_id"])')
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message 'Q1=所有成员，Q2=站内通知' --session-id frontier-session --message-id frontier-message-1)
  event_id=$(printf '%s' "$observed" | json_field event_id)
  if [[ "$observed" != *'"status": "observed_round"'* ]]; then
    _fail "frontier observation should identify the round"
  elif ! python3 - "$MODULE/.work-meta.json" "$gate_one" "$gate_two" "$event_id" <<'PY'
import json, sys
path, gate_one, gate_two, event_id = sys.argv[1:]
items = json.load(open(path))['decision_gates']['items']
by_id = {item['gate_id']: item for item in items}
assert by_id[gate_one]['mode'] == 'frontier'
assert by_id[gate_one]['round_id'] == by_id[gate_two]['round_id']
assert by_id[gate_one]['answer_candidates'][0]['event_id'] == event_id
assert by_id[gate_two]['answer_candidates'][0]['event_id'] == event_id
PY
  then
    _fail "one event should be recorded on every question in the same frontier round"
  elif ! python3 "$GATE" answer-round "$MODULE" --event-id "$event_id" \
      --selection "$gate_one=all" --selection "$gate_two=in-app" >/dev/null; then
    _fail "answer-round should explicitly answer both questions"
  else
    python3 "$GATE" consume "$MODULE" --gate-id "$gate_one" --decision-id D41 >/dev/null
    python3 "$GATE" consume "$MODULE" --gate-id "$gate_two" --decision-id D42 >/dev/null
    pass_test
  fi
  teardown_fixture
}

test_frontier_round_keeps_partial_answers_pending() {
  start_test "decision gate: Design frontier round 部分回答仍阻止落盘"
  setup_fixture

  local opened gate_one gate_two observed event_id
  opened=$(open_frontier_round)
  gate_one=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["gate_id"])')
  gate_two=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[1]["gate_id"])')
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message '只确定通知对象：所有成员' --session-id frontier-session --message-id frontier-message-2)
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer-round "$MODULE" --event-id "$event_id" --selection "$gate_one=all" >/dev/null
  if python3 "$GATE" guard-pending-write "$MODULE" >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "an unanswered frontier question must block product artifact writes"
  elif ! grep -q '尚未回答' /tmp/decision-gate.err.$$; then
    _fail "partial frontier answer should explain the remaining pending question"
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_frontier_remaining_question_keeps_round_binding() {
  start_test "decision gate: frontier 部分回答后剩余单题仍走 answer-round"
  setup_fixture

  local opened gate_one gate_two observed event_id second_event
  opened=$(open_frontier_round)
  gate_one=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["gate_id"])')
  gate_two=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[1]["gate_id"])')
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message '只确定通知对象：所有成员' --session-id frontier-session --message-id frontier-message-partial-1)
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer-round "$MODULE" --event-id "$event_id" --selection "$gate_one=all" >/dev/null

  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message 'Q2=站内通知' --session-id frontier-session --message-id frontier-message-partial-2)
  second_event=$(printf '%s' "$observed" | json_field event_id)
  if [[ "$observed" != *'"status": "observed_round"'* ]] \
     || [[ "$observed" != *"\"$gate_two\""* ]]; then
    _fail "the last pending frontier question must remain identified as its round"
  elif python3 "$GATE" answer "$MODULE" --gate-id "$gate_two" --event-id "$second_event" \
      >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "a frontier question must not fall back to the sequential answer command"
  elif ! python3 "$GATE" answer-round "$MODULE" --event-id "$second_event" \
      --selection "$gate_two=in-app" >/dev/null; then
    _fail "answer-round should accept the remaining question explicitly"
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_frontier_requires_shared_understanding_before_spec_and_ready() {
  start_test "decision gate: frontier 清空后必须确认 shared-understanding 才能写 spec 和 ready"
  setup_fixture

  local opened gate_one gate_two observed event_id shared shared_gate shared_event checkpoint pack approved
  opened=$(open_frontier_round)
  gate_one=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["gate_id"])')
  gate_two=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[1]["gate_id"])')
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message 'Q1=所有成员，Q2=站内通知' --session-id frontier-session --message-id frontier-message-3)
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer-round "$MODULE" --event-id "$event_id" \
    --selection "$gate_one=all" --selection "$gate_two=in-app" >/dev/null
  python3 "$GATE" consume "$MODULE" --gate-id "$gate_one" --decision-id D51 >/dev/null
  python3 "$GATE" consume "$MODULE" --gate-id "$gate_two" --decision-id D52 >/dev/null

  if python3 "$GATE" guard-pending-write "$MODULE" --artifact spec \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "frontier without shared-understanding must block spec writes"
    teardown_fixture
    return
  fi
  shared=$(python3 "$GATE" open-shared "$MODULE" \
    --summary "通知对象和首版渠道已明确" --message "请确认我们对本轮范围和行为理解一致" \
    --session-id shared-session)
  shared_gate=$(printf '%s' "$shared" | json_field gate_id)
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message '确认，理解一致' --session-id shared-session --message-id shared-message-1)
  shared_event=$(printf '%s' "$observed" | json_field event_id)
  if [[ "$observed" != *'"kind": "shared-understanding"'* ]]; then
    _fail "shared-understanding observation should identify its receipt kind"
    rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
    teardown_fixture
    return
  fi
  python3 "$GATE" confirm-shared "$MODULE" --gate-id "$shared_gate" --event-id "$shared_event" >/dev/null
  if python3 "$GATE" guard-pending-write "$MODULE" --artifact spec \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "answered but unconsumed shared-understanding must still block spec"
    rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
    teardown_fixture
    return
  fi
  python3 "$GATE" consume-shared "$MODULE" --gate-id "$shared_gate" >/dev/null
  if ! python3 "$GATE" guard-pending-write "$MODULE" --artifact spec >/dev/null 2>&1; then
    _fail "consumed shared-understanding should authorize spec writes"
    rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
    teardown_fixture
    return
  fi

  printf '\n## D51 通知对象\n\n- 结论：所有成员。\n\n## D52 通知渠道\n\n- 结论：站内通知。\n' >> "$MODULE/decisions.md"
  git -C "$T" add -- docs/modules/access/decisions.md docs/modules/access/.work-meta.json
  if ! python3 "$GATE" check-staged --repo-root "$T" >/dev/null 2>&1; then
    _fail "a consumed shared-understanding receipt should allow the authority commit"
    rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
    teardown_fixture
    return
  fi
  git -C "$T" commit -q -m "approve frontier decisions"
  checkpoint=$(git -C "$T" rev-parse HEAD)
  pack="$T/.pm-workflow/context/access.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$pack" >/dev/null
  approved=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$pack")
  if ! python3 "$BUILD_CONTRACT" ready "$MODULE" \
    --approved-source-hash "$approved" --checkpoint-commit "$checkpoint" \
    --context-pack "$pack" --target-path "$TARGET" >/dev/null; then
    _fail "ready should accept the bound shared-understanding receipt"
  elif ! python3 - "$MODULE/.work-meta.json" "$shared_gate" "$checkpoint" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
contract = meta['decision_gates']
shared = next(item for item in contract['items'] if item['gate_id'] == sys.argv[2])
assert shared['kind'] == 'shared-understanding'
assert shared['status'] == 'consumed'
assert shared['consumed_by']['checkpoint_commit'] == sys.argv[3]
assert contract['ready_authorization']['shared_understanding_gate_id'] == sys.argv[2]
PY
  then
    _fail "ready should bind the shared-understanding receipt to its checkpoint"
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
  teardown_fixture
}

test_frontier_free_text_answer_is_bound_to_one_question() {
  start_test "decision gate: frontier 自由回答显式绑定到对应问题"
  setup_fixture

  local opened gate_id observed event_id
  opened=$(python3 "$GATE" open-round "$MODULE" \
    --kind product-model --round-summary "通知例外" \
    --question '{"summary":"例外对象","message":"哪些成员不应收到通知？","options":[{"id":"none","label":"没有例外"}],"allow_free_text":true}' \
    --session-id free-text-session)
  gate_id=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["gate_id"])')
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message 'Q1：停用账号和外部访客不接收' --session-id free-text-session --message-id free-text-message-1)
  event_id=$(printf '%s' "$observed" | json_field event_id)
  if ! python3 "$GATE" answer-round "$MODULE" --event-id "$event_id" \
      --free-text "$gate_id=停用账号和外部访客不接收" >/dev/null; then
    _fail "frontier free-text answer should be accepted explicitly"
  elif ! python3 - "$MODULE/.work-meta.json" "$gate_id" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))['decision_gates']['items']
item = next(value for value in items if value['gate_id'] == sys.argv[2])
assert item['status'] == 'answered'
assert item['answer']['selected_option_id'] is None
assert item['answer']['free_text'] == '停用账号和外部访客不接收'
PY
  then
    _fail "frontier free-text answer should remain attached to its own gate"
  else
    pass_test
  fi
  teardown_fixture
}

test_new_frontier_invalidates_old_shared_understanding() {
  start_test "decision gate: shared-understanding 之后的新 frontier 必须重新确认"
  setup_fixture

  local opened gate_one gate_two observed event_id shared shared_gate shared_event new_gate
  opened=$(open_frontier_round)
  gate_one=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["gate_id"])')
  gate_two=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[1]["gate_id"])')
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message 'Q1=所有成员，Q2=站内通知' --session-id frontier-session --message-id frontier-message-4)
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer-round "$MODULE" --event-id "$event_id" \
    --selection "$gate_one=all" --selection "$gate_two=in-app" >/dev/null
  python3 "$GATE" consume "$MODULE" --gate-id "$gate_one" --decision-id D61 >/dev/null
  python3 "$GATE" consume "$MODULE" --gate-id "$gate_two" --decision-id D62 >/dev/null
  shared=$(python3 "$GATE" open-shared "$MODULE" \
    --summary "通知基础范围已明确" --message "请确认我们理解一致" --session-id shared-session-2)
  shared_gate=$(printf '%s' "$shared" | json_field gate_id)
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message '确认' --session-id shared-session-2 --message-id shared-message-2)
  shared_event=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" confirm-shared "$MODULE" --gate-id "$shared_gate" --event-id "$shared_event" >/dev/null
  python3 "$GATE" consume-shared "$MODULE" --gate-id "$shared_gate" >/dev/null

  opened=$(python3 "$GATE" open-round "$MODULE" \
    --kind product-model --round-summary "新发现的失败提醒" \
    --question '{"summary":"失败提醒对象","message":"发送失败时提醒谁？","options":[{"id":"admins","label":"管理员"},{"id":"sender","label":"触发人"}],"allow_free_text":false}' \
    --session-id frontier-session-2)
  new_gate=$(printf '%s' "$opened" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["gate_id"])')
  observed=$(python3 "$GATE" observe --repo-root "$T" \
    --message '管理员' --session-id frontier-session-2 --message-id frontier-message-5)
  event_id=$(printf '%s' "$observed" | json_field event_id)
  python3 "$GATE" answer-round "$MODULE" --event-id "$event_id" --selection "$new_gate=admins" >/dev/null
  python3 "$GATE" consume "$MODULE" --gate-id "$new_gate" --decision-id D63 >/dev/null
  printf '\n新失败提醒规则。\n' >> "$MODULE/spec.md"
  printf '\n## D61 通知对象\n\n- 结论：所有成员。\n\n## D62 通知渠道\n\n- 结论：站内通知。\n\n## D63 失败提醒\n\n- 结论：提醒管理员。\n' >> "$MODULE/decisions.md"
  git -C "$T" add -- docs/modules/access/spec.md docs/modules/access/decisions.md docs/modules/access/.work-meta.json

  if python3 "$GATE" guard-pending-write "$MODULE" --artifact spec \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "an old shared-understanding receipt must not cover a later frontier"
  elif python3 "$GATE" check-staged --repo-root "$T" \
    >/tmp/decision-gate.$$ 2>/tmp/decision-gate.err.$$; then
    _fail "staged spec must require a shared-understanding receipt after the latest frontier"
  elif ! grep -q 'shared-understanding' /tmp/decision-gate.err.$$; then
    _fail "stale shared-understanding rejection should identify the missing fresh confirmation"
  else
    pass_test
  fi
  rm -f /tmp/decision-gate.$$ /tmp/decision-gate.err.$$
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
test_frontier_round_binds_one_event_to_multiple_questions
test_frontier_round_keeps_partial_answers_pending
test_frontier_remaining_question_keeps_round_binding
test_frontier_requires_shared_understanding_before_spec_and_ready
test_frontier_free_text_answer_is_bound_to_one_question
test_new_frontier_invalidates_old_shared_understanding
test_old_ready_without_receipts_is_unverifiable
report_results "decision-gate"
