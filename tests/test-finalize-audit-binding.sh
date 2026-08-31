#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BINDING="$ROOT/scripts/finalize-audit-binding.py"
JUDGE="$ROOT/scripts/finalize-audit-readonly-judge.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-finalize-audit-binding.XXXXXX")
  AUDIT="$T/.pm-workflow/audits/demo"
  mkdir -p "$AUDIT"
  cat > "$AUDIT/finalize-run.json" <<'JSON'
{
  "schema_version": 1,
  "runner": "finalize-work",
  "implementation_commit": "abc123",
  "source_hash": "source123",
  "required_timing_phases": ["currentness", "final-validation", "landing", "documentation"],
  "allowed_limited_timing_phases": [],
  "semantic_checks": [],
  "updated_at": "2026-08-23T12:00:00+08:00"
}
JSON
  cat > "$AUDIT/final-validation.json" <<'JSON'
{
  "schema_version": 1,
  "check": "final-validation",
  "status": "pass",
  "implementation_commit": "abc123",
  "source_hash": "source123",
  "commands": []
}
JSON
  cat > "$AUDIT/timing.json" <<'JSON'
{
  "schema_version": 1,
  "entries": [
    {"id":"c","phase":"currentness","status":"pass"},
    {"id":"v","phase":"final-validation","status":"pass"},
    {"id":"l","phase":"landing","status":"pass"},
    {"id":"d","phase":"documentation","status":"pass"}
  ]
}
JSON
  printf '# Consumer\n' > "$T/README.md"
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  git -C "$T" add -A
  git -C "$T" commit -qm baseline
}

teardown_fixture() { rm -rf "$T"; }

write_verifier_binding() {
  local marker="$AUDIT/finalize-run.json"
  local backend="${1:-child}"
  local run_id="${2:-verifier-test-001}"
  python3 - "$marker" "$backend" "$run_id" <<'PY'
import json
import sys

path, backend, run_id = sys.argv[1:]
marker = json.load(open(path, encoding="utf-8"))
marker["verifier_binding"] = {
    "schema_version": 1,
    "role": "verifier",
    "backend": backend,
    "independent": backend != "main-fallback",
    "run_id": run_id,
    "host": "test-host",
    "model": "test-model",
    "implementation_commit": marker["implementation_commit"],
    "source_hash": marker["source_hash"],
    "status": "degraded" if backend == "main-fallback" else "pass",
}
json.dump(marker, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

write_judge() {
  local path="$1"
  local evidence_digest_value="$2"
  local run_id="${3:-judge-test-001}"
  local backend="${4:-child}"
  local checks_json="${5:-[]}"
  local pass_value="${6:-true}"
  python3 - "$path" "$evidence_digest_value" "$run_id" "$backend" "$checks_json" "$pass_value" <<'PY'
import json
import sys

path, evidence_digest_value, run_id, backend, checks_json, pass_value = sys.argv[1:]
payload = {
    "pass": pass_value == "true",
    "reason": "test Judge result",
    "evidence_digest": evidence_digest_value,
    "checks": json.loads(checks_json),
    "provenance": {
        "role": "judge",
        "backend": backend,
        "host": "test-judge-host",
        "model": "test-judge-model",
        "run_id": run_id,
        "framework_revision": "test-framework",
        "tool_sha256": "test-tool",
    },
}
json.dump(payload, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
}

test_bind_and_attach_independent_judge() {
  start_test "finalize-audit-binding: bind revisions and attach independent Judge"
  setup_fixture
  binding="$AUDIT/audit-binding.json"
  judge_json="$T/judge.json"
  if ! python3 "$BINDING" bind --consumer-root "$T" --audit-dir ".pm-workflow/audits/demo" \
    --framework-root "$ROOT" --runner-run-id runner-123 >/tmp/finalize-audit-binding.$$ 2>&1; then
    _fail "binding should succeed"
    cat /tmp/finalize-audit-binding.$$ >&2
    teardown_fixture
    return
  fi
  if ! python3 - "$binding" <<'PY'
import json, sys
binding = json.load(open(sys.argv[1]))
assert binding["provenance"]["framework_revision"]
assert isinstance(binding["provenance"]["framework_clean"], bool)
assert len(binding["provenance"]["tool_files"]) == 5
assert set(binding["provenance"]["tool_files"]) == {
    "scripts/finalize-audit-binding.py",
    "scripts/finalize-audit-readonly-judge.py",
    "scripts/finalize-work.py",
    "scripts/_lib/agent_roles.py",
    "scripts/_lib/finalize_audit.py",
}
assert binding["provenance"]["tool_digest"]
assert binding["provenance"]["consumer_revision"]
assert binding["provenance"]["consumer_clean_at_bind"] is True
assert binding["judge"]["status"] == "pending"
assert binding["evidence"]["digest"]
PY
  then
    _fail "binding must include revisions, evidence digest, and pending Judge"
    teardown_fixture
    return
  fi
  if ! python3 "$JUDGE" --binding "$binding" --consumer-root "$T" > "$judge_json"; then
    _fail "independent Judge should pass the frozen audit"
    cat "$judge_json" >&2
    teardown_fixture
    return
  fi
  if ! python3 "$BINDING" attach-judge --binding "$binding" --judge-json "$judge_json" >/dev/null; then
    _fail "Judge receipt should attach"
  elif ! python3 "$BINDING" verify --binding "$binding" --consumer-root "$T" --require-judge >/dev/null; then
    _fail "attached binding should verify"
  elif ! python3 - "$binding" <<'PY'
import json, sys
binding = json.load(open(sys.argv[1]))
assert binding["judge"]["framework_revision"]
assert binding["judge"]["tool_sha256"]
assert binding["judge"]["role"] == "judge"
assert binding["judge"]["backend"] == "external"
assert binding["judge"]["independent"] is True
PY
  then
    _fail "attached Judge must bind its framework revision and tool source"
  else
    pass_test
  fi
  rm -f /tmp/finalize-audit-binding.$$
  teardown_fixture
}

test_tampered_audit_is_rejected() {
  start_test "finalize-audit-binding: tampered audit evidence is rejected"
  setup_fixture
  binding="$AUDIT/audit-binding.json"
  python3 "$BINDING" bind --consumer-root "$T" --audit-dir ".pm-workflow/audits/demo" \
    --framework-root "$ROOT" >/dev/null
  printf '\nchanged\n' >> "$AUDIT/timing.json"
  if python3 "$BINDING" verify --binding "$binding" --consumer-root "$T" >/tmp/finalize-audit-binding-tamper.$$ 2>&1; then
    _fail "tampered audit must not verify"
  else
    pass_test
  fi
  rm -f /tmp/finalize-audit-binding-tamper.$$
  teardown_fixture
}

test_prelanding_fallback_is_explicitly_non_independent() {
  start_test "finalize-audit-binding: main fallback is explicit and Judge remains independent"
  setup_fixture
  write_verifier_binding main-fallback fallback-verifier-001
  binding="$AUDIT/audit-binding.json"
  if ! python3 "$BINDING" bind --consumer-root "$T" --audit-dir ".pm-workflow/audits/demo" \
    --framework-root "$ROOT" --runner-role verifier --runner-backend main-fallback \
    --runner-run-id fallback-verifier-001 --pre-landing >/dev/null; then
    _fail "pre-landing fallback binding should succeed"
    teardown_fixture
    return
  fi
  if ! python3 - "$binding" <<'PY'
import json, sys
binding = json.load(open(sys.argv[1], encoding="utf-8"))
provenance = binding["provenance"]
assert provenance["runner_role"] == "verifier"
assert provenance["runner_backend"] == "main-fallback"
assert provenance["runner_independent"] is False
assert binding["phase"] == "pre-landing"
PY
  then
    _fail "fallback binding must be marked non-independent"
    teardown_fixture
    return
  fi
  digest_value=$(python3 - "$binding" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["evidence"]["digest"])
PY
  )
  judge_json="$T/judge.json"
  write_judge "$judge_json" "$digest_value" independent-judge-001 child '[]'
  if ! python3 "$BINDING" attach-judge --binding "$binding" --judge-json "$judge_json" >/dev/null; then
    _fail "independent Judge should attach after fallback Verifier"
  elif ! python3 "$BINDING" verify --binding "$binding" --consumer-root "$T" \
    --pre-landing --require-judge >/dev/null; then
    _fail "fallback binding with independent Judge should verify"
  else
    pass_test
  fi
  teardown_fixture
}

test_judge_rejects_digest_run_reuse_and_scope_mismatch() {
  start_test "finalize-audit-binding: Judge rejects digest mismatch, run reuse, and semantic scope drift"
  setup_fixture
  python3 - "$AUDIT/finalize-run.json" <<'PY'
import json, sys
path = sys.argv[1]
marker = json.load(open(path, encoding="utf-8"))
marker["semantic_checks"] = ["coverage"]
json.dump(marker, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
  binding="$AUDIT/audit-binding.json"
  python3 "$BINDING" bind --consumer-root "$T" --audit-dir ".pm-workflow/audits/demo" \
    --framework-root "$ROOT" --runner-run-id verifier-test-001 >/dev/null
  digest_value=$(python3 - "$binding" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["evidence"]["digest"])
PY
  )
  judge_json="$T/judge.json"

  write_judge "$judge_json" wrong-digest judge-digest-mismatch child '[{"name":"coverage","status":"pass"}]'
  if python3 "$BINDING" attach-judge --binding "$binding" --judge-json "$judge_json" >/tmp/finalize-audit-binding.$$ 2>&1; then
    _fail "Judge with a mismatched evidence digest must be rejected"
    teardown_fixture
    return
  fi

  write_judge "$judge_json" "$digest_value" verifier-test-001 child '[{"name":"coverage","status":"pass"}]'
  if python3 "$BINDING" attach-judge --binding "$binding" --judge-json "$judge_json" >/tmp/finalize-audit-binding.$$ 2>&1; then
    _fail "Judge must not reuse the Verifier run id"
    teardown_fixture
    return
  fi

  write_judge "$judge_json" "$digest_value" judge-scope-mismatch child '[{"name":"other-check","status":"pass"}]'
  if python3 "$BINDING" attach-judge --binding "$binding" --judge-json "$judge_json" >/tmp/finalize-audit-binding.$$ 2>&1; then
    _fail "Judge semantic checks must exactly cover the marker checks"
    teardown_fixture
    return
  fi

  write_judge "$judge_json" "$digest_value" judge-valid child '[{"name":"coverage","status":"pass"}]'
  if ! python3 "$BINDING" attach-judge --binding "$binding" --judge-json "$judge_json" >/dev/null; then
    _fail "valid Judge should attach after rejected receipts"
  elif ! python3 - "$binding" "$digest_value" "$AUDIT/semantic-judge.json" <<'PY'
import json
import sys

binding_path, expected_digest, judge_path = sys.argv[1:]
binding = json.load(open(binding_path, encoding="utf-8"))
assert binding["evidence"]["digest"] == expected_digest
assert "semantic-judge.json" not in binding["evidence"]["files"]
assert binding["judge"]["evidence_digest"] == expected_digest
assert json.load(open(judge_path, encoding="utf-8"))["pass"] is True
PY
  then
    _fail "attached Judge must not alter the evidence digest or omit its receipt"
  else
    pass_test
  fi
  rm -f /tmp/finalize-audit-binding.$$
  teardown_fixture
}

test_mechanical_failure_cannot_be_overridden_by_judge() {
  start_test "finalize-audit-binding: mechanical failure remains blocking after Judge pass"
  setup_fixture
  binding="$AUDIT/audit-binding.json"
  python3 "$BINDING" bind --consumer-root "$T" --audit-dir ".pm-workflow/audits/demo" \
    --framework-root "$ROOT" --runner-run-id verifier-test-002 >/dev/null
  digest_value=$(python3 - "$binding" <<'PY'
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["evidence"]["digest"])
PY
  )
  judge_json="$T/judge.json"
  write_judge "$judge_json" "$digest_value" judge-mechanical-pass child '[]'
  if ! python3 "$BINDING" attach-judge --binding "$binding" --judge-json "$judge_json" >/dev/null; then
    _fail "baseline Judge should attach"
    teardown_fixture
    return
  fi
  python3 - "$AUDIT/final-validation.json" <<'PY'
import json, sys
path = sys.argv[1]
artifact = json.load(open(path, encoding="utf-8"))
artifact["status"] = "fail"
json.dump(artifact, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
  if python3 "$BINDING" verify --binding "$binding" --consumer-root "$T" --require-judge \
    >/tmp/finalize-audit-binding-mechanical.$$ 2>&1; then
    _fail "a passing Judge must not override a failed mechanical artifact"
  else
    pass_test
  fi
  rm -f /tmp/finalize-audit-binding-mechanical.$$
  teardown_fixture
}

test_bind_and_attach_independent_judge
test_tampered_audit_is_rejected
test_prelanding_fallback_is_explicitly_non_independent
test_judge_rejects_digest_run_reuse_and_scope_mismatch
test_mechanical_failure_cannot_be_overridden_by_judge
report_results "finalize-audit-binding"
