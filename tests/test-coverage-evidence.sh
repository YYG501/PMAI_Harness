#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$FRAMEWORK_ROOT/scripts/coverage-evidence.py"

test_coverage_requires_semantic_state_confirmation() {
  start_test "coverage-evidence: machine coverage plus explicit state confirmation binds current candidate"
  local t module plan artifacts output
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-coverage-evidence.XXXXXX")
  module="$t/docs/modules/demo"
  plan="$t/checks.json"
  artifacts="$t/captures"
  output="$t/.pm-workflow/audits/demo/coverage.json"
  mkdir -p "$module" "$artifacts/local"
  cat > "$module/.work-meta.json" <<'JSON'
{"build":{"implementation_commit":"abc123","approved_source_hash":"source123","finalization":{"requested_at":"2026-08-13T10:00:00+08:00","requested_commit":"abc123"}}}
JSON
  cat > "$plan" <<'JSON'
{"schema_version":"1.0","module":"demo","checks":[{"id":"detail","must_have_text":["详情"],"must_check_buttons":[{"text":"保存","disabled":false}],"must_cover_states":["success","error"]}]}
JSON
  cat > "$artifacts/local/detail.json" <<'JSON'
{"url":"http://127.0.0.1/detail","title":"详情","textPreview":"详情","buttons":[{"text":"保存","disabled":false}]}
JSON
  python3 "$RUNNER" --repo-root "$t" --module-dir "$module" --plan "$plan" \
    --artifacts "$artifacts" --output "$output" >/tmp/coverage-evidence.$$ 2>/tmp/coverage-evidence.err.$$
  local blocked=$?
  if [ "$blocked" = "0" ]; then
    _fail "declared states must require explicit semantic confirmation"
    rm -rf "$t"; return
  fi
  if ! python3 "$RUNNER" --repo-root "$t" --module-dir "$module" --plan "$plan" \
    --artifacts "$artifacts" --output "$output" --confirm-state detail \
    >/tmp/coverage-evidence.$$ 2>/tmp/coverage-evidence.err.$$; then
    _fail "confirmed clean coverage should pass"
    cat /tmp/coverage-evidence.err.$$ >&2
  elif ! python3 - "$output" <<'PY'
import json, sys
artifact = json.load(open(sys.argv[1]))
assert artifact["check"] == "coverage"
assert artifact["status"] == "pass"
assert artifact["implementation_commit"] == "abc123"
assert artifact["source_hash"] == "source123"
assert artifact["items"] == [{
    "id": "detail", "status": "pass", "machine_issues": [],
    "declared_states": ["success", "error"], "states_confirmed": True,
}]
PY
  then
    _fail "coverage artifact binding mismatch"
  else
    pass_test
  fi
  rm -f /tmp/coverage-evidence.$$ /tmp/coverage-evidence.err.$$
  rm -rf "$t"
}

test_machine_gap_cannot_be_confirmed_away() {
  start_test "coverage-evidence: semantic confirmation cannot erase machine P0/P1 gaps"
  local t module plan artifacts output
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-coverage-evidence-gap.XXXXXX")
  module="$t/docs/modules/demo"
  plan="$t/checks.json"
  artifacts="$t/captures"
  output="$t/coverage.json"
  mkdir -p "$module" "$artifacts/local"
  printf '%s\n' '{"build":{"implementation_commit":"abc123","approved_source_hash":"source123","finalization":{"requested_at":"now","requested_commit":"abc123"}}}' > "$module/.work-meta.json"
  printf '%s\n' '{"checks":[{"id":"detail","must_have_text":["必须出现"],"must_cover_states":[]}]}' > "$plan"
  printf '%s\n' '{"textPreview":"缺失"}' > "$artifacts/local/detail.json"
  python3 "$RUNNER" --repo-root "$t" --module-dir "$module" --plan "$plan" \
    --artifacts "$artifacts" --output "$output" >/tmp/coverage-evidence.$$ 2>/tmp/coverage-evidence.err.$$
  local rc=$?
  if [ "$rc" = "1" ] && python3 - "$output" <<'PY'
import json, sys
artifact = json.load(open(sys.argv[1]))
assert artifact["status"] == "needs-review"
assert artifact["items"][0]["status"] == "needs-review"
assert artifact["items"][0]["machine_issues"][0]["severity"] == "P1"
PY
  then
    pass_test
  else
    _fail "machine coverage gap should remain visible: rc=$rc"
  fi
  rm -f /tmp/coverage-evidence.$$ /tmp/coverage-evidence.err.$$
  rm -rf "$t"
}

test_structured_coverage_is_revalidated_at_close() {
  start_test "coverage-evidence: close revalidates structured artifact instead of trusting evidence status"
  local t
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-coverage-validator.XXXXXX")
  mkdir -p "$t/.pm-workflow/audits/demo" "$t/docs/modules/demo"
  if PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 - "$t" <<'PY'
import json
import sys
from pathlib import Path

from _lib import build_evidence

root = Path(sys.argv[1])
module_dir = root / "docs/modules/demo"
artifact_path = root / ".pm-workflow/audits/demo/coverage.json"
artifact = {
    "schema_version": 1,
    "check": "coverage",
    "status": "pass",
    "implementation_commit": "commit-1",
    "source_hash": "source-1",
    "items": [{
        "id": "detail", "status": "pass", "machine_issues": [],
        "declared_states": ["error"], "states_confirmed": True,
    }],
    "issues": [],
}
artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
build = {
    "approved_source_hash": "source-1",
    "implementation_commit": "commit-1",
    "acceptance": {"evidence": [{
        "name": "coverage", "status": "pass", "source_hash": "source-1",
        "commit": "commit-1", "checked_at": "now",
        "artifact": str(artifact_path.relative_to(root)),
    }]},
}
build_evidence.canonical_final_checks = lambda meta: ["coverage"]
build_evidence.validate_fresh_evidence(module_dir, build)
artifact["items"][0]["states_confirmed"] = False
artifact_path.write_text(json.dumps(artifact), encoding="utf-8")
try:
    build_evidence.validate_fresh_evidence(module_dir, build)
except SystemExit as exc:
    assert "must_cover_states" in str(exc)
else:
    raise AssertionError("tampered structured coverage should fail")
PY
  then
    pass_test
  else
    _fail "structured coverage currentness validation failed"
  fi
  rm -rf "$t"
}

test_coverage_requires_semantic_state_confirmation
test_machine_gap_cannot_be_confirmed_away
test_structured_coverage_is_revalidated_at_close
report_results "coverage-evidence"
