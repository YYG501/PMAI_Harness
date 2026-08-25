#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/active-build-fixture.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
UI_HELPER="$REPO_ROOT/scripts/ui-impact.py"
UI_GUARD="$REPO_ROOT/hooks/ui-impact-guard.cjs"
FINALIZE_GUARD="$REPO_ROOT/hooks/finalize-route-guard.cjs"

json_context() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("additionalContext", ""))'
}

json_decision() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecision", ""))'
}

test_ui_helper_detects_primitive_override_risk() {
  start_test "ui-impact: 首次尺寸修改识别共享 primitive 覆盖风险"
  local t output rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-ui-impact.XXXXXX")
  mkdir -p "$t/src/components/ui" "$t/src/pages"
  printf 'const width = "sm:max-w-sm";\n' > "$t/src/components/ui/dialog.tsx"
  printf 'import { DialogContent } from "@/components/ui/dialog";\nexport const page = <DialogContent className="max-w-[800px]" />;\n' > "$t/src/pages/Page.tsx"
  output=$(PYTHONDONTWRITEBYTECODE=1 python3 "$UI_HELPER" inspect \
    --repo-root "$t" --path src/pages/Page.tsx --proposed-text 'max-w-[960px]' 2>&1)
  rc=$?
  if [ "$rc" = 1 ] && python3 -c '
import json,sys
data=json.loads(sys.stdin.read())
assert data["status"] == "needs-review"
assert data["primitive_refs"][0]["path"] == "src/components/ui/dialog.tsx"
assert "sm:max-w-sm" in data["primitive_refs"][0]["constraints"]
assert {item["code"] for item in data["findings"]} == {"primitive-override-risk", "actual-size-required"}
' <<<"$output"; then
    pass_test
  else
    _fail "primitive override risk report mismatch: $output"
  fi
  rm -rf "$t"
}

test_ui_guard_blocks_first_edit_and_allows_explicit_override() {
  start_test "ui-impact: hook 阻断未处理 primitive 的首次编辑并放行显式覆盖"
  local t blocked allowed
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-ui-guard.XXXXXX")
  git -C "$t" init -q -b main
  git -C "$t" config user.email test@example.com
  git -C "$t" config user.name Test
  mkdir -p "$t/src/components/ui" "$t/src/pages"
  printf 'const width = "sm:max-w-sm";\n' > "$t/src/components/ui/dialog.tsx"
  printf 'import { DialogContent } from "@/components/ui/dialog";\nexport const page = <DialogContent className="max-w-[800px]" />;\n' > "$t/src/pages/Page.tsx"
  git -C "$t" add . && git -C "$t" commit -qm init
  blocked=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"'"$t"'","tool_input":{"file_path":"'"$t"'/src/pages/Page.tsx","old_string":"max-w-[800px]","new_string":"max-w-[960px]"}}' |
    (cd "$t" && node "$UI_GUARD"))
  allowed=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"'"$t"'","tool_input":{"file_path":"'"$t"'/src/pages/Page.tsx","old_string":"max-w-[800px]","new_string":"!max-w-[960px]"}}' |
    (cd "$t" && node "$UI_GUARD"))
  if [ "$(json_decision <<<"$blocked")" = "deny" ] &&
     echo "$blocked" | grep -q "sm:max-w-sm" &&
     [ "$(json_decision <<<"$allowed")" = "allow" ] &&
     echo "$allowed" | grep -q "size 断言"; then
    pass_test
  else
    _fail "UI guard decision mismatch: blocked=$blocked allowed=$allowed"
  fi
  rm -rf "$t"
}

test_ui_size_verification_is_deterministic() {
  start_test "ui-impact: 实际尺寸 helper 对容差外结果失败"
  local t output
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-ui-size.XXXXXX")
  if PYTHONDONTWRITEBYTECODE=1 python3 "$UI_HELPER" verify-size \
    --selector '[data-testid=dialog]' --expected 960 --actual 961 --tolerance 2 \
    --output "$t/pass.json" >/dev/null &&
    ! PYTHONDONTWRITEBYTECODE=1 python3 "$UI_HELPER" verify-size \
      --selector '[data-testid=dialog]' --expected 960 --actual 970 --tolerance 2 \
      --output "$t/fail.json" >/dev/null; then
    output=$(cat "$t/fail.json")
    if echo "$output" | grep -q '"status": "fail"'; then
      pass_test
    else
      _fail "size failure artifact mismatch: $output"
    fi
  else
    _fail "size helper pass/fail contract mismatch"
  fi
  rm -rf "$t"
}

test_finalize_route_blocks_manual_close_after_pm_authorization() {
  start_test "finalize-route: PM 定稿授权后必须先进入统一 runner"
  active_build_fixture_setup prototype iterating
  local intent out blocked before_semantic allowed semantic_after semantic_chain record_after wrong_record duplicate
  intent=$(mktemp -d "${TMPDIR:-/tmp}/pmai-finalize-intent.XXXXXX")
  out=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","prompt":"好，可以了，提交合并吧"}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  before_semantic=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"python3 scripts/prototype-boundary.py docs/modules/demo --output .pm-workflow/audits/demo/prototype-boundary.json"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  blocked=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"npm test"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  allowed=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"python3 scripts/finalize-candidate.py --module-dir docs/modules/demo"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  semantic_after=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"python3 scripts/prototype-boundary.py docs/modules/demo --output .pm-workflow/audits/demo/prototype-boundary.json"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  semantic_chain=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"python3 scripts/prototype-boundary.py docs/modules/demo --output .pm-workflow/audits/demo/prototype-boundary.json && git commit -am bypass"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  record_after=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"python3 scripts/build-contract.py record-evidence docs/modules/demo --name prototype-boundary --status pass --artifact .pm-workflow/audits/demo/prototype-boundary.json"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  wrong_record=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"python3 scripts/build-contract.py record-evidence docs/modules/demo --name browser-acceptance --status pass --artifact .pm-workflow/audits/demo/browser-acceptance.json"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  python3 - "$ACTIVE_BUILD_FIXTURE/docs/modules/demo/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
meta = json.loads(path.read_text(encoding="utf-8"))
meta["build"]["acceptance"]["evidence"].append({"name": "prototype-boundary"})
path.write_text(json.dumps(meta), encoding="utf-8")
PY
  duplicate=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-1","tool_input":{"command":"python3 scripts/prototype-boundary.py docs/modules/demo --output .pm-workflow/audits/demo/prototype-boundary.json"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  if [[ "$out" == *"FINALIZE"* ]] &&
     [ "$(json_decision <<<"$before_semantic")" = "deny" ] &&
     [ "$(json_decision <<<"$blocked")" = "deny" ] &&
     [[ "$blocked" == *"finalize-candidate.py"* ]] &&
     [ "$(json_decision <<<"$allowed")" = "allow" ] &&
     [ "$(json_decision <<<"$semantic_after")" = "allow" ] &&
     [ "$(json_decision <<<"$semantic_chain")" = "deny" ] &&
     [ "$(json_decision <<<"$record_after")" = "allow" ] &&
     [ "$(json_decision <<<"$wrong_record")" = "deny" ] &&
     [ "$(json_decision <<<"$duplicate")" = "deny" ]; then
    pass_test
  else
    _fail "finalize route decision mismatch: out=$out before_semantic=$before_semantic blocked=$blocked allowed=$allowed semantic_after=$semantic_after semantic_chain=$semantic_chain record_after=$record_after wrong_record=$wrong_record duplicate=$duplicate"
  fi
  rm -rf "$intent"
  active_build_fixture_teardown
}

test_non_finalize_prompt_clears_short_lived_intent() {
  start_test "finalize-route: PM 新反馈清除短期定稿意图"
  active_build_fixture_setup prototype iterating
  local intent first cleared after
  intent=$(mktemp -d "${TMPDIR:-/tmp}/pmai-finalize-intent-clear.XXXXXX")
  first=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-2","prompt":"定稿"}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  cleared=$(printf '%s' '{"hook_event_name":"UserPromptSubmit","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-2","prompt":"这个按钮还要改一下"}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  after=$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"'"$ACTIVE_BUILD_FIXTURE"'","session_id":"session-2","tool_input":{"command":"npm test"}}' |
    (cd "$ACTIVE_BUILD_FIXTURE" && PMAI_FINALIZE_INTENT_DIR="$intent" node "$FINALIZE_GUARD"))
  if [[ "$first" == *"FINALIZE"* ]] &&
     [ -z "$cleared" ] && [ -z "$after" ]; then
    pass_test
  else
    _fail "finalize intent should clear on new PM feedback: first=$first cleared=$cleared after=$after"
  fi
  rm -rf "$intent"
  active_build_fixture_teardown
}

test_ui_helper_detects_primitive_override_risk
test_ui_guard_blocks_first_edit_and_allows_explicit_override
test_ui_size_verification_is_deterministic
test_finalize_route_blocks_manual_close_after_pm_authorization
test_non_finalize_prompt_clears_short_lived_intent
report_results "ui-impact"
