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
assert len(binding["provenance"]["tool_files"]) == 3
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

test_bind_and_attach_independent_judge
test_tampered_audit_is_rejected
report_results "finalize-audit-binding"
