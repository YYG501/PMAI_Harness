#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVAL="$REPO_ROOT/scripts/skill-eval.py"
RUNNER="$REPO_ROOT/scripts/skill-eval-codex-runner.py"
JUDGE="$REPO_ROOT/scripts/skill-eval-readonly-judge.py"
FAKE_CODEX="$REPO_ROOT/tests/fixtures/fake-codex-cli.py"

test_real_adapter_protocol() {
  start_test "session-eval adapter: Codex Runner runtime evidence + readonly Judge"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-session-adapter.XXXXXX")
  if PMAI_CODEX_COMMAND="python3 $FAKE_CODEX" \
     PMAI_FRAMEWORK_ROOT="$REPO_ROOT" \
     PMAI_INPUT_COST_PER_1K_USD=1 \
     PMAI_OUTPUT_COST_PER_1K_USD=2 \
     python3 "$EVAL" --mode session --case natural-language-finalize \
       --runner-command "python3 $RUNNER" \
       --judge-command "python3 $JUDGE" \
       --require-runner --require-judge --require-runtime-evidence \
       --results-dir "$T" >/tmp/session-eval-adapter.$$ 2>&1 && \
     python3 - "$T/natural-language-finalize.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
runner = payload["runner_result"]
manifest = payload["evidence_manifest"]
assert runner["provenance"]["framework_revision"]
assert runner["provenance"]["consumer_revision"]
assert runner["runtime"]["token_usage"]["status"] == "reported"
assert runner["runtime"]["token_usage"] == {
    "status": "reported",
    "input_tokens": 120,
    "output_tokens": 30,
    "total_tokens": 150,
}
assert runner["runtime"]["cost"]["status"] == "reported"
assert runner["runtime"]["failure"]["status"] == "none"
assert runner["diagnostics"] == ["non-fatal skill context diagnostic"]
assert manifest["independent_evidence"]["runtime"] == runner["runtime"]
assert "provider_event" in manifest["independent_evidence"]["event_log"]["kinds"]
assert payload["judge_result"]["provenance"]["run_id"] != runner["provenance"]["run_id"]
PY
  then
    pass_test
  else
    _fail "real adapter protocol should pass"
    cat /tmp/session-eval-adapter.$$ >&2
  fi
  rm -rf "$T" /tmp/session-eval-adapter.$$
}

test_legacy_token_event_compatibility() {
  start_test "session-eval adapter: 兼容旧 token_count 事件"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-session-legacy.XXXXXX")
  if PMAI_CODEX_COMMAND="python3 $FAKE_CODEX --legacy-tokens" \
     PMAI_FRAMEWORK_ROOT="$REPO_ROOT" \
     python3 "$EVAL" --mode session --case natural-language-finalize \
       --runner-command "python3 $RUNNER" \
       --judge-command "python3 $JUDGE" \
       --require-runner --require-judge --require-runtime-evidence \
       --results-dir "$T" >/tmp/session-eval-legacy.$$ 2>&1 && \
     python3 - "$T/natural-language-finalize.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["runner_result"]["runtime"]["token_usage"] == {
    "status": "reported",
    "input_tokens": 120,
    "output_tokens": 30,
    "total_tokens": 150,
}
PY
  then
    pass_test
  else
    _fail "legacy token_count event should remain supported"
    cat /tmp/session-eval-legacy.$$ >&2
  fi
  rm -rf "$T" /tmp/session-eval-legacy.$$
}

test_runtime_requirement_rejects_old_runner() {
  start_test "session-eval adapter: 旧 runner 缺 runtime evidence 时阻断"
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $REPO_ROOT/tests/fixtures/fake-skill-eval.py" \
      --judge-command "python3 $REPO_ROOT/tests/fixtures/fake-skill-eval.py" \
      --require-runner --require-judge --require-runtime-evidence >/tmp/session-eval-runtime.$$ 2>&1; then
    _fail "old runner without runtime evidence should fail"
  elif grep -q 'runner.runtime' /tmp/session-eval-runtime.$$; then
    pass_test
  else
    _fail "runtime evidence failure should be explicit"
    cat /tmp/session-eval-runtime.$$ >&2
  fi
  rm -f /tmp/session-eval-runtime.$$
}

test_runner_refuses_current_directory_fallback() {
  start_test "session-eval adapter: 无隔离 workspace 时拒绝使用当前目录"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-session-no-harness.XXXXXX")
  if (
    cd "$T" || exit 1
    printf '%s\n' '{"evaluation_id":"eval-no-harness","case":{"id":"natural-language-finalize"}}' |
      PMAI_CODEX_COMMAND="python3 $FAKE_CODEX" \
      PMAI_FRAMEWORK_ROOT="$REPO_ROOT" \
      python3 "$RUNNER" >/tmp/session-eval-no-harness.$$ 2>&1
  ); then
    _fail "runner must reject cases without an isolated harness workspace"
  elif grep -q 'refusing to use the current working directory' /tmp/session-eval-no-harness.$$ &&
       [ ! -e "$T/PRODUCT-STATE.md" ]; then
    pass_test
  else
    _fail "missing harness failure should be explicit and side-effect free"
    cat /tmp/session-eval-no-harness.$$ >&2
  fi
  rm -rf "$T" /tmp/session-eval-no-harness.$$
}

test_runner_injects_harness_file_boundaries() {
  start_test "session-eval adapter: runner 将只读文件边界注入 prompt"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-session-boundary.XXXXXX")
  mkdir -p "$T/workspace"
  printf 'fixture\n' >"$T/workspace/PRODUCT-STATE.md"
  : >"$T/events.jsonl"
  if printf '%s\n' "$(python3 - "$T" <<'PY'
import json
import sys
root = sys.argv[1]
print(json.dumps({
    "evaluation_id": "eval-boundary",
    "case": {
        "id": "readonly-boundary",
        "input": {"prompt": "只做只读判断", "context": []},
        "skills": [],
        "expected": {},
        "forbidden": {},
        "harness": {
            "workspace": root + "/workspace",
            "event_log": root + "/events.jsonl",
            "expected_changed_paths": [],
            "protected_paths": ["PRODUCT-STATE.md"],
            "expected_unchanged_paths": ["PRODUCT-STATE.md"],
        },
    },
}))
PY
)" | PMAI_CODEX_COMMAND="python3 $FAKE_CODEX --assert-readonly-prompt" \
    PMAI_FRAMEWORK_ROOT="$REPO_ROOT" python3 "$RUNNER" >"$T/result.json" 2>"$T/runner.stderr"; then
    pass_test
  else
    _fail "runner should inject read-only Harness boundaries"
    cat "$T/result.json" "$T/runner.stderr" >&2
  fi
  rm -rf "$T"
}

test_nonzero_exit_includes_stderr() {
  start_test "session-eval adapter: 非零退出保留 stderr 失败原因"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-session-stderr.XXXXXX")
  mkdir -p "$T/workspace"
  : > "$T/events.jsonl"
  printf '%s\n' "{\"evaluation_id\":\"eval-stderr\",\"case\":{\"id\":\"natural-language-finalize\",\"harness\":{\"workspace\":\"$T/workspace\",\"event_log\":\"$T/events.jsonl\"}}}" |
    PMAI_CODEX_COMMAND="python3 $FAKE_CODEX --fail-with-stderr" \
    PMAI_FRAMEWORK_ROOT="$REPO_ROOT" \
    python3 "$RUNNER" >"$T/result.json" 2>"$T/runner.stderr"
  if python3 - "$T/result.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
failure = payload["runtime"]["failure"]
assert failure["status"] == "error"
assert "fake stderr failure" in failure["reason"]
PY
  then
    pass_test
  else
    _fail "non-zero Codex exit should include stderr"
    cat "$T/result.json" "$T/runner.stderr" >&2
  fi
  rm -rf "$T"
}

test_completed_result_survives_post_result_stream_disconnect() {
  start_test "session-eval adapter: 完整结果后的 stream disconnect 交给独立证据复核"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-session-post-result-disconnect.XXXXXX")
  if PMAI_CODEX_COMMAND="python3 $FAKE_CODEX --disconnect-after-result" \
     PMAI_FRAMEWORK_ROOT="$REPO_ROOT" \
     python3 "$EVAL" --mode session --case natural-language-finalize \
       --runner-command "python3 $RUNNER" \
       --judge-command "python3 $JUDGE" \
       --require-runner --require-judge --require-runtime-evidence \
       --results-dir "$T" >/tmp/session-eval-post-result.$$ 2>&1 && \
     python3 - "$T/natural-language-finalize.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
runner = payload["runner_result"]
assert runner["status"] == "pass"
assert runner["runtime"]["failure"]["status"] == "none"
assert runner["runtime"]["transport"]["status"] == "warning"
assert any("recoverable transport warning" in item for item in runner["diagnostics"])
PY
  then
    pass_test
  else
    _fail "complete result after stream disconnect should reach independent judge"
    cat /tmp/session-eval-post-result.$$ >&2
  fi
  rm -rf "$T" /tmp/session-eval-post-result.$$
}

test_completed_result_survives_transport_turn_failure() {
  start_test "session-eval adapter: 完整结果后的 transport turn failure 可恢复"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-session-post-result-transport.XXXXXX")
  if PMAI_CODEX_COMMAND="python3 $FAKE_CODEX --disconnect-after-result --turn-failed-transport" \
     PMAI_FRAMEWORK_ROOT="$REPO_ROOT" \
     python3 "$EVAL" --mode session --case natural-language-finalize \
       --runner-command "python3 $RUNNER" \
       --judge-command "python3 $JUDGE" \
       --require-runner --require-judge --require-runtime-evidence \
       --results-dir "$T" >/tmp/session-eval-post-result-transport.$$ 2>&1 && \
     python3 - "$T/natural-language-finalize.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
runner = payload["runner_result"]
assert runner["status"] == "pass"
assert runner["runtime"]["failure"]["status"] == "none"
assert runner["runtime"]["transport"]["status"] == "warning"
PY
  then
    pass_test
  else
    _fail "transport turn failure after complete marker should be recoverable"
    cat /tmp/session-eval-post-result-transport.$$ >&2
  fi
  rm -rf "$T" /tmp/session-eval-post-result-transport.$$
}

test_real_adapter_protocol
test_legacy_token_event_compatibility
test_runtime_requirement_rejects_old_runner
test_runner_refuses_current_directory_fallback
test_runner_injects_harness_file_boundaries
test_nonzero_exit_includes_stderr
test_completed_result_survives_post_result_stream_disconnect
test_completed_result_survives_transport_turn_failure
report_results "session-eval-adapters"
