#!/usr/bin/env bash
# Regression coverage for /pmai-feedback and exact current-session location.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$REPO_ROOT/skills/feedback/SKILL.md"
ANALYSIS_REF="$REPO_ROOT/skills/feedback/references/session-analysis.md"
HANDOFF_REF="$REPO_ROOT/skills/feedback/references/framework-handoff.md"
LOCATOR="$REPO_ROOT/scripts/current-session.py"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
README="$REPO_ROOT/README.md"
DESIGN="$REPO_ROOT/skills/design/SKILL.md"
META="$REPO_ROOT/skills/meta/SKILL.md"
AGENTS_TEMPLATE="$REPO_ROOT/templates/AGENTS.md.tmpl"
CLAUDE_TEMPLATE="$REPO_ROOT/templates/CLAUDE.md.tmpl"

write_session() {
  local path="$1"
  local session_id="$2"
  local cwd="$3"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "{\"type\":\"session_meta\",\"payload\":{\"id\":\"$session_id\",\"cwd\":\"$cwd\",\"timestamp\":\"2026-07-22T00:00:00Z\",\"originator\":\"test\"}}" > "$path"
  printf '%s\n' '{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello"}]}}' >> "$path"
}

test_public_contract() {
  start_test "feedback: 公开入口与只读合同"

  assert_file_exists "$SKILL" "feedback skill should exist" || return
  assert_file_contains "$SKILL" "name: pmai-feedback" "frontmatter should expose pmai-feedback" || return
  assert_file_contains "$SKILL" "只读反馈出口" "skill should be read-only" || return
  assert_file_contains "$SKILL" "修改消费仓文件" "skill should ban consumer writes" || return
  assert_file_contains "$SKILL" "修改 PMAI 框架仓" "skill should ban framework writes" || return
  assert_file_contains "$SKILL" "不得创建反馈文件" "skill should not write feedback artifacts" || return
  assert_file_contains "$SKILL" "current-session.py" "skill should use exact locator" || return
  assert_file_contains "$SKILL" "按 mtime" "skill should ban recent-file guessing" || return
  assert_file_contains "$SKILL" "原始会话文件绝对路径" "handoff must include transcript path" || return
  pass_test
}

test_analysis_and_handoff_contracts() {
  start_test "feedback: 分析归位与框架交接合同"

  assert_file_exists "$ANALYSIS_REF" "session analysis reference should exist" || return
  assert_file_exists "$HANDOFF_REF" "framework handoff reference should exist" || return
  assert_file_contains "$ANALYSIS_REF" "execution_gap" "analysis should distinguish execution gaps" || return
  assert_file_contains "$ANALYSIS_REF" "framework_contract_gap" "analysis should distinguish contract gaps" || return
  assert_file_contains "$ANALYSIS_REF" "consumer_project" "analysis should keep project issues local" || return
  assert_file_contains "$ANALYSIS_REF" "从第一条记录连续读到 EOF" "analysis should require full coverage" || return
  assert_file_contains "$HANDOFF_REF" "会话 ID" "handoff should include session id" || return
  assert_file_contains "$HANDOFF_REF" "原始会话文件" "handoff should include transcript path" || return
  assert_file_contains "$HANDOFF_REF" "待分析证据" "handoff should treat transcript as evidence" || return
  assert_file_contains "$HANDOFF_REF" "不修改文件" "handoff should wait for PM before edits" || return
  pass_test
}

test_codex_active_session_is_exact() {
  start_test "current-session: CODEX_THREAD_ID 精确命中 active JSONL"

  local tmp repo codex session_id transcript out rc
  tmp=$(mktemp -d)
  repo="$tmp/consumer"
  codex="$tmp/codex"
  session_id="019f-test-active"
  transcript="$codex/sessions/2026/07/22/rollout-$session_id.jsonl"
  mkdir -p "$repo"
  write_session "$transcript" "$session_id" "$repo"

  out=$(CODEX_THREAD_ID="$session_id" CODEX_HOME="$codex" \
    python3 "$LOCATOR" --repo-root "$repo" --host auto 2>&1)
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "exact active lookup failed: $out"
    rm -rf "$tmp"
    return
  fi
  if ! LOCATOR_OUT="$out" EXPECTED_PATH="$transcript" python3 -c '
import json, os
data = json.loads(os.environ["LOCATOR_OUT"])
assert data["exact"] is True
assert data["host"] == "codex"
assert data["transcript_state"] == "active"
assert os.path.realpath(data["transcript_path"]) == os.path.realpath(os.environ["EXPECTED_PATH"])
'; then
    _fail "active lookup JSON contract mismatch: $out"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_codex_archived_session_is_exact() {
  start_test "current-session: 精确命中 archived JSONL"

  local tmp repo codex session_id transcript out rc
  tmp=$(mktemp -d)
  repo="$tmp/consumer"
  codex="$tmp/codex"
  session_id="019f-test-archived"
  transcript="$codex/archived_sessions/rollout-$session_id.jsonl"
  mkdir -p "$repo"
  write_session "$transcript" "$session_id" "$repo"

  out=$(CODEX_THREAD_ID="$session_id" CODEX_HOME="$codex" \
    python3 "$LOCATOR" --repo-root "$repo" 2>&1)
  rc=$?
  if [ "$rc" != "0" ] || ! echo "$out" | grep -q '"transcript_state": "archived"'; then
    _fail "archived lookup should succeed exactly: $out"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_locator_fails_closed() {
  start_test "current-session: 无 ID、多候选、cwd 不符和未验证宿主均阻断"

  local tmp repo codex session_id active archived out rc
  tmp=$(mktemp -d)
  repo="$tmp/consumer"
  codex="$tmp/codex"
  session_id="019f-test-ambiguous"
  active="$codex/sessions/2026/07/22/rollout-$session_id.jsonl"
  archived="$codex/archived_sessions/rollout-$session_id.jsonl"
  mkdir -p "$repo"

  out=$(env -u CODEX_THREAD_ID CODEX_HOME="$codex" \
    python3 "$LOCATOR" --repo-root "$repo" --host auto 2>&1)
  rc=$?
  if [ "$rc" = "0" ] || ! echo "$out" | grep -q "禁止按最近修改时间猜测"; then
    _fail "missing id should fail without recent-file fallback: $out"
    rm -rf "$tmp"
    return
  fi

  write_session "$active" "$session_id" "$repo"
  write_session "$archived" "$session_id" "$repo"
  out=$(CODEX_THREAD_ID="$session_id" CODEX_HOME="$codex" \
    python3 "$LOCATOR" --repo-root "$repo" 2>&1)
  rc=$?
  if [ "$rc" = "0" ] || ! echo "$out" | grep -q "找到多个"; then
    _fail "multiple exact-id candidates should fail: $out"
    rm -rf "$tmp"
    return
  fi

  rm -f "$active" "$archived"
  write_session "$active" "$session_id" "$tmp/another-repo"
  out=$(CODEX_THREAD_ID="$session_id" CODEX_HOME="$codex" \
    python3 "$LOCATOR" --repo-root "$repo" 2>&1)
  rc=$?
  if [ "$rc" = "0" ] || ! echo "$out" | grep -q "不属于指定消费仓"; then
    _fail "cwd mismatch should fail: $out"
    rm -rf "$tmp"
    return
  fi

  out=$(python3 "$LOCATOR" --repo-root "$repo" --host claude-code \
    --session-id "019f-test-claude" 2>&1)
  rc=$?
  if [ "$rc" = "0" ] || ! echo "$out" | grep -q "尚未实现经过验证"; then
    _fail "unverified host should fail closed: $out"
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  pass_test
}

test_public_surface_replaces_skill_improve() {
  start_test "feedback: 替换旧公开入口且保留正确分流"

  assert_file_missing "$REPO_ROOT/skills/skill-improve/SKILL.md" "old public skill should be removed" || return
  assert_file_contains "$DOCTOR" "feedback" "doctor should expose feedback" || return
  if grep -q "skill-improve" "$DOCTOR"; then
    _fail "doctor should not expose skill-improve"
    return
  fi
  assert_file_contains "$README" "/pmai-feedback" "README should list feedback" || return
  if grep -q "/pmai-skill-improve" "$README"; then
    _fail "README should not list old public entry"
    return
  fi
  assert_file_contains "$DESIGN" "/pmai-feedback" "design should route workflow feedback" || return
  assert_file_contains "$META" "/pmai-feedback" "meta should route workflow feedback" || return
  assert_file_contains "$AGENTS_TEMPLATE" "/pmai-feedback" "consumer AGENTS should expose feedback route" || return
  assert_file_contains "$CLAUDE_TEMPLATE" "/pmai-feedback" "consumer CLAUDE should list feedback entry" || return
  pass_test
}

test_no_machine_bound_paths() {
  start_test "feedback: 框架资产不含机器绑定路径"

  if grep -R "/Users/" "$REPO_ROOT/skills/feedback" "$LOCATOR" >/tmp/pmai_feedback_paths.$$ 2>&1; then
    _fail "feedback assets should not hardcode /Users paths"
    rm -f /tmp/pmai_feedback_paths.$$
    return
  fi
  rm -f /tmp/pmai_feedback_paths.$$
  pass_test
}

test_public_contract
test_analysis_and_handoff_contracts
test_codex_active_session_is_exact
test_codex_archived_session_is_exact
test_locator_fails_closed
test_public_surface_replaces_skill_improve
test_no_machine_bound_paths

report_results "feedback-skill"
