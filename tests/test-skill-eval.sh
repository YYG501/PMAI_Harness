#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EVAL="$REPO_ROOT/scripts/skill-eval.py"
FAKE="$REPO_ROOT/tests/fixtures/fake-skill-eval.py"
FAKE_SEMANTIC="$REPO_ROOT/tests/fixtures/fake-semantic-judge.py"
RELEASE_GATE="$REPO_ROOT/tests/run-release-gate.sh"

test_schema_and_static_cases() {
  start_test "skill-eval: schema、touchfiles 与静态案例"
  if python3 "$EVAL" --mode validate >/tmp/skill-eval.$$ 2>&1 && \
     python3 "$EVAL" --mode static >>/tmp/skill-eval.$$ 2>&1; then
    pass_test
  else
    _fail "schema/static should pass"
    cat /tmp/skill-eval.$$ >&2
  fi
}

test_missing_runner_is_explicit() {
  start_test "skill-eval: runner 缺失时显式 skip，gate 模式显式 fail"
  if ! env -u PMAI_SKILL_EVAL_RUNNER -u PMAI_SKILL_EVAL_JUDGE \
      python3 "$EVAL" --mode session --case natural-language-finalize >/tmp/skill-eval-skip.$$ 2>&1; then
    _fail "default missing runner should skip without failing"
    return
  fi
  if ! grep -q "SKIP natural-language-finalize: session runner 未配置" /tmp/skill-eval-skip.$$; then
    _fail "missing runner skip should be visible"
    return
  fi
  if env -u PMAI_SKILL_EVAL_RUNNER -u PMAI_SKILL_EVAL_JUDGE -u PMAI_SKILL_EVAL_SEMANTIC_JUDGE \
      python3 "$EVAL" --mode session --case natural-language-finalize --require-runner >/tmp/skill-eval-required.$$ 2>&1; then
    _fail "required missing runner should fail"
    return
  fi
  if ! grep -q "FAIL natural-language-finalize: session runner 未配置" /tmp/skill-eval-required.$$; then
    _fail "required missing runner failure should be visible"
    return
  fi
  pass_test
}

test_runner_and_judge_protocol() {
  start_test "skill-eval: runner/judge 结果合同与落盘"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-eval.XXXXXX")
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE" \
      --judge-command "python3 $FAKE" \
      --require-runner --require-judge --results-dir "$T" >/tmp/skill-eval-run.$$ 2>&1 && \
      [ -f "$T/natural-language-finalize.json" ] && \
      python3 - "$T/natural-language-finalize.json" <<'PY'
import hashlib
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
manifest = payload["evidence_manifest"]
assert manifest["independent_evidence"]["changed_paths"] == ["PRODUCT-STATE.md"]
assert manifest["independent_evidence"]["protected_violations"] == []
assert manifest["independent_evidence"]["event_log"]["kinds"] == ["command", "lifecycle", "tool"]
assert manifest["independent_evidence"]["event_log"]["count"] >= 3
core = {key: value for key, value in manifest.items() if key != "digest"}
expected = hashlib.sha256(
    json.dumps(core, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
assert manifest["digest"] == expected
PY
  then
    pass_test
  else
    _fail "runner/judge protocol should pass and persist evidence"
    cat /tmp/skill-eval-run.$$ >&2
  fi
  rm -rf "$T"
}

test_runner_claim_without_workspace_change_fails() {
  start_test "skill-eval: runner 伪成功但 fixture 无实际修改时失败"
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE --no-change" \
      --judge-command "python3 $FAKE" >/tmp/skill-eval-no-change.$$ 2>&1; then
    _fail "runner claim without workspace change should fail"
  elif grep -q '未观察到预期修改' /tmp/skill-eval-no-change.$$; then
    pass_test
  else
    _fail "pseudo-success failure should cite independent workspace evidence"
    cat /tmp/skill-eval-no-change.$$ >&2
  fi
  rm -f /tmp/skill-eval-no-change.$$
}

test_readonly_harness_accepts_no_change() {
  start_test "skill-eval: 只读 session 的零写入结果可被独立证据接受"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-eval-readonly.XXXXXX")
  mkdir -p "$T/cases"
  jq '.id = "readonly-session" | .title = "只读 session" | .harness.expected_changed_paths = [] | .harness.expected_unchanged_paths = ["PRODUCT-STATE.md"]' \
    "$REPO_ROOT/evals/cases/natural-language-finalize.json" >"$T/cases/readonly-session.json"
  cat >"$T/touchfiles.json" <<EOF
{"schema_version":1,"cases":{"readonly-session":["evals/fixtures/natural-language-finalize/README.md"]}}
EOF
  if python3 "$EVAL" --mode session --cases-dir "$T/cases" --touchfiles "$T/touchfiles.json" \
      --case readonly-session --runner-command "python3 $FAKE" --judge-command "python3 $FAKE" \
      --require-runner --require-judge --results-dir "$T/results" >/tmp/skill-eval-readonly.$$ 2>&1 && \
      grep -q 'SUMMARY passed=1 failed=0 skipped=0 judge_skipped=0' /tmp/skill-eval-readonly.$$; then
    pass_test
  else
    _fail "readonly session should pass with zero workspace changes"
    cat /tmp/skill-eval-readonly.$$ >&2
  fi
  rm -rf "$T" /tmp/skill-eval-readonly.$$
}

test_readonly_harness_detects_change() {
  start_test "skill-eval: 只读 session 修改预期不变文件时失败"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-eval-readonly-drift.XXXXXX")
  mkdir -p "$T/cases"
  jq '.id = "readonly-session" | .title = "只读 session" | .harness.expected_changed_paths = [] | .harness.expected_unchanged_paths = ["PRODUCT-STATE.md"]' \
    "$REPO_ROOT/evals/cases/natural-language-finalize.json" >"$T/cases/readonly-session.json"
  cat >"$T/touchfiles.json" <<EOF
{"schema_version":1,"cases":{"readonly-session":["evals/fixtures/natural-language-finalize/README.md"]}}
EOF
  if python3 "$EVAL" --mode session --cases-dir "$T/cases" --touchfiles "$T/touchfiles.json" \
      --case readonly-session --runner-command "python3 $FAKE --touch-unchanged" --judge-command "python3 $FAKE" \
      --require-runner --require-judge >/tmp/skill-eval-readonly-drift.$$ 2>&1; then
    _fail "readonly session should reject changed expected-unchanged paths"
  elif grep -q '预期不变文件被修改' /tmp/skill-eval-readonly-drift.$$; then
    pass_test
  else
    _fail "readonly violation should be explicit"
    cat /tmp/skill-eval-readonly-drift.$$ >&2
  fi
  rm -rf "$T" /tmp/skill-eval-readonly-drift.$$
}

test_manifest_includes_configured_evidence_files() {
  start_test "skill-eval: manifest 保留配置的真相文件快照"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-eval-evidence.XXXXXX")
  mkdir -p "$T/cases"
  jq '.id = "readonly-evidence" | .title = "只读 evidence" | .harness.expected_changed_paths = [] | .harness.expected_unchanged_paths = ["PRODUCT.md"] | .harness.protected_paths = ["PRODUCT.md"] | .harness.evidence_paths = ["PRODUCT.md"]' \
    "$REPO_ROOT/evals/cases/natural-language-finalize.json" >"$T/cases/readonly-evidence.json"
  cat >"$T/touchfiles.json" <<EOF
{"schema_version":1,"cases":{"readonly-evidence":["evals/fixtures/natural-language-finalize/README.md"]}}
EOF
  if python3 "$EVAL" --mode session --cases-dir "$T/cases" --touchfiles "$T/touchfiles.json" \
      --case readonly-evidence --runner-command "python3 $FAKE" --judge-command "python3 $FAKE" \
      --require-runner --require-judge --results-dir "$T/results" >/tmp/skill-eval-evidence.$$ 2>&1 && \
      python3 - "$T/results/readonly-evidence.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
evidence = payload["evidence_manifest"]["independent_evidence"]["evidence_files"]
assert evidence["paths"] == ["PRODUCT.md"]
assert evidence["baseline"]["PRODUCT.md"]["kind"] == "file"
assert evidence["baseline"]["PRODUCT.md"]["content"]
assert evidence["final"]["PRODUCT.md"]["sha256"] == evidence["baseline"]["PRODUCT.md"]["sha256"]
PY
  then
    pass_test
  else
    _fail "configured evidence file snapshots should be present in manifest"
    cat /tmp/skill-eval-evidence.$$ >&2
  fi
  rm -rf "$T" /tmp/skill-eval-evidence.$$
}

test_protected_path_change_fails() {
  start_test "skill-eval: fixture 保护路径被修改时失败"
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE --touch-protected" \
      --judge-command "python3 $FAKE" >/tmp/skill-eval-protected.$$ 2>&1; then
    _fail "protected path change should fail"
  elif grep -q '越界修改' /tmp/skill-eval-protected.$$; then
    pass_test
  else
    _fail "protected path failure should be explicit"
    cat /tmp/skill-eval-protected.$$ >&2
  fi
  rm -f /tmp/skill-eval-protected.$$
}

test_tampered_digest_fails() {
  start_test "skill-eval: judge 回传篡改 digest 时失败"
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE" \
      --judge-command "python3 $FAKE --tamper-digest" >/tmp/skill-eval-tampered.$$ 2>&1; then
    _fail "tampered digest should fail"
  elif grep -q 'evidence_digest' /tmp/skill-eval-tampered.$$; then
    pass_test
  else
    _fail "tampered digest failure should be explicit"
    cat /tmp/skill-eval-tampered.$$ >&2
  fi
  rm -f /tmp/skill-eval-tampered.$$
}

test_runner_without_judge_cannot_pass() {
  start_test "skill-eval: runner 自报结果且无 judge 时只能 skip"
  if ! env -u PMAI_SKILL_EVAL_JUDGE python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE" >/tmp/skill-eval-no-judge.$$ 2>&1; then
    _fail "missing optional judge should skip without failing"
    cat /tmp/skill-eval-no-judge.$$ >&2
    return
  fi
  if grep -q '^PASS natural-language-finalize:' /tmp/skill-eval-no-judge.$$ \
     || ! grep -q 'SUMMARY passed=0 failed=0 skipped=1 judge_skipped=1' \
       /tmp/skill-eval-no-judge.$$; then
    _fail "runner-only result must not count as a session pass"
    cat /tmp/skill-eval-no-judge.$$ >&2
    return
  fi
  pass_test
}

test_semantic_judge_required() {
  start_test "skill-eval: capability gate 缺 semantic Judge 时阻断"
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE" \
      --judge-command "python3 $FAKE" \
      --require-runner --require-judge --require-semantic-judge >/tmp/skill-eval-no-semantic.$$ 2>&1; then
    _fail "missing semantic judge should fail"
  elif grep -q 'semantic Judge 未配置' /tmp/skill-eval-no-semantic.$$; then
    pass_test
  else
    _fail "missing semantic judge failure should be explicit"
    cat /tmp/skill-eval-no-semantic.$$ >&2
  fi
  rm -f /tmp/skill-eval-no-semantic.$$
}

test_semantic_judge_protocol() {
  start_test "skill-eval: semantic Judge 评分合同与证据绑定"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-eval-semantic.XXXXXX")
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE" \
      --judge-command "python3 $FAKE" \
      --semantic-judge-command "python3 $FAKE_SEMANTIC" \
      --require-runner --require-judge --require-semantic-judge --results-dir "$T" >/tmp/skill-eval-semantic.$$ 2>&1 && \
      python3 - "$T/natural-language-finalize.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
semantic = payload["semantic_judge_result"]
assert semantic["assessment_type"] == "semantic-llm-v1"
assert semantic["pass"] is True
assert semantic["criterion_scores"]
assert semantic["evidence_digest"] == payload["evidence_manifest"]["digest"]
PY
  then
    pass_test
  else
    _fail "semantic judge result should be validated and persisted"
    cat /tmp/skill-eval-semantic.$$ >&2
  fi
  rm -rf "$T" /tmp/skill-eval-semantic.$$
}

test_semantic_judge_rejection_is_hard_gate() {
  start_test "skill-eval: semantic Judge pass=false 必须阻断"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-eval-semantic-fail.XXXXXX")
  FAIL_JUDGE="$T/fail-semantic.py"
  cat >"$FAIL_JUDGE" <<'PY'
import json
import sys

payload = json.load(sys.stdin)
case = payload["case"]
manifest = payload.get("evidence_manifest") or {}
print(json.dumps({
    "case_id": case["id"],
    "evaluation_id": payload["evaluation_id"],
    "assessment_type": "semantic-llm-v1",
    "pass": False,
    "reason": "intentional semantic failure",
    "criterion_scores": [
        {"criterion": criterion, "score": 1, "reason": "intentional failure"}
        for criterion in case["judge"]["rubric"]
    ],
    "findings": ["intentional failure"],
    "root_causes": ["test"],
    "provenance": {
        "host": "semantic-judge-fixture",
        "model": "fixture-semantic-judge",
        "run_id": f"semantic-failure-{payload['evaluation_id']}",
    },
    "reviewed_evidence": ["transcript", "tool_calls", "file_diff", "independent_evidence", "manifest", "digest"],
    "evidence_digest": manifest.get("digest", ""),
}, ensure_ascii=False))
PY
  if PMAI_CODEX_COMMAND="python3 $FAKE" \
     PMAI_FRAMEWORK_ROOT="$REPO_ROOT" \
     python3 "$EVAL" --mode session --case natural-language-finalize \
       --runner-command "python3 $FAKE" \
       --judge-command "python3 $FAKE" \
       --semantic-judge-command "python3 $FAIL_JUDGE" \
       --require-runner --require-judge --require-semantic-judge --results-dir "$T" >/tmp/skill-eval-semantic-fail.$$ 2>&1; then
    _fail "semantic judge pass=false should fail"
  elif grep -q 'semantic judge 未通过: intentional semantic failure' /tmp/skill-eval-semantic-fail.$$; then
    pass_test
  else
    _fail "semantic judge rejection should be explicit"
    cat /tmp/skill-eval-semantic-fail.$$ >&2
  fi
  rm -rf "$T" /tmp/skill-eval-semantic-fail.$$
}

test_judge_must_be_independent() {
  start_test "skill-eval: judge 必须使用独立 run_id"
  if python3 "$EVAL" --mode session --case natural-language-finalize \
      --runner-command "python3 $FAKE" \
      --judge-command "python3 $FAKE --reuse-run-id" \
      --require-runner --require-judge >/tmp/skill-eval-same-run.$$ 2>&1; then
    _fail "judge reusing runner run_id should fail"
    return
  fi
  if ! grep -q 'judge 必须使用独立于 runner 的 run_id' /tmp/skill-eval-same-run.$$; then
    _fail "independent judge failure should be explicit"
    cat /tmp/skill-eval-same-run.$$ >&2
    return
  fi
  pass_test
}

test_release_gate_requires_external_capabilities() {
  start_test "skill-eval: stable release gate 缺 runner/judge 时阻断"
  if env -u PMAI_SKILL_EVAL_RUNNER -u PMAI_SKILL_EVAL_JUDGE \
      bash "$RELEASE_GATE" >/tmp/skill-eval-release-gate.$$ 2>&1; then
    _fail "release gate should fail without runner and judge"
    return
  fi
  if ! grep -q 'Release gate blocked: missing PMAI_SKILL_EVAL_RUNNER PMAI_SKILL_EVAL_JUDGE PMAI_SKILL_EVAL_SEMANTIC_JUDGE' \
      /tmp/skill-eval-release-gate.$$; then
    _fail "release gate should name both missing capabilities"
    cat /tmp/skill-eval-release-gate.$$ >&2
    return
  fi
  pass_test
}

test_schema_and_static_cases
test_missing_runner_is_explicit
test_runner_and_judge_protocol
test_runner_claim_without_workspace_change_fails
test_readonly_harness_accepts_no_change
test_readonly_harness_detects_change
test_manifest_includes_configured_evidence_files
test_protected_path_change_fails
test_tampered_digest_fails
test_runner_without_judge_cannot_pass
test_semantic_judge_required
test_semantic_judge_protocol
test_semantic_judge_rejection_is_hard_gate
test_judge_must_be_independent
test_release_gate_requires_external_capabilities
report_results "skill-eval"
