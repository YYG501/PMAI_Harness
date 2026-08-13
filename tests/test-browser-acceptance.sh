#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER="$FRAMEWORK_ROOT/scripts/browser-acceptance.py"

test_browser_flows_run_in_one_chain_and_one_artifact() {
  start_test "browser-acceptance: affected flows run in one persistent chain"
  local t module manifest audit fake
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-browser-acceptance.XXXXXX")
  module="$t/docs/modules/licenses"
  manifest="$t/.pm-workflow/audits/licenses/browser-manifest.json"
  audit="$t/.pm-workflow/audits/licenses/browser-acceptance.json"
  fake="$t/fake-browse"
  mkdir -p "$module" "$(dirname "$manifest")"
  cat > "$module/.work-meta.json" <<'JSON'
{
  "build": {
    "contract_version": 4,
    "implementation_commit": "abc123",
    "approved_source_hash": "source123",
    "finalization": {
      "requested_at": "2026-08-06T10:00:00+08:00",
      "requested_commit": "abc123"
    }
  }
}
JSON
  cat > "$manifest" <<'JSON'
{
  "schema_version": 1,
  "base_url": "http://127.0.0.1:3000",
  "flows": [
    {
      "id": "license-list",
      "route": "/ops/licenses",
      "covers": ["smoke", "visual", "behavior"],
      "commands": [
        ["goto", "{base_url}/ops/licenses"],
        ["wait", "main"],
        ["screenshot", "{audit_dir}/license-list.png"],
        ["click", "button[data-testid=filter]"],
        ["is", "visible", "[data-testid=filter-panel]"]
      ]
    }
  ]
}
JSON
  cat > "$fake" <<'SH'
#!/usr/bin/env bash
test "$1" = "chain" || exit 2
payload="$FAKE_BROWSE_COUNT.payload"
cat > "$payload"
python3 -c 'import json,pathlib,sys
commands=json.load(open(sys.argv[1])); assert len(commands)==5
for command in commands:
    if command[0]=="screenshot": pathlib.Path(command[1]).write_bytes(b"png")
path=pathlib.Path(sys.argv[2]); path.write_text(path.read_text()+"1\n" if path.exists() else "1\n")' \
  "$payload" "$FAKE_BROWSE_COUNT"
SH
  chmod +x "$fake"

  if ! FAKE_BROWSE_COUNT="$t/count" python3 "$RUNNER" \
    --repo-root "$t" --module-dir "$module" --manifest "$manifest" \
    --audit "$audit" --browse-bin "$fake" \
    --legacy-check browser-smoke --legacy-check visual --legacy-check behavior \
    >/tmp/browser-acceptance.$$ 2>/tmp/browser-acceptance.err.$$; then
    _fail "browser batch should pass"
    cat /tmp/browser-acceptance.err.$$ >&2
  elif ! python3 - "$audit" "$t/count" <<'PY'
import json, sys
from pathlib import Path
artifact = json.load(open(sys.argv[1]))
assert artifact["status"] == "pass"
assert artifact["active_browser_smoke"] is True
assert artifact["single_chain_invocation"] is True
assert artifact["covers"] == ["behavior", "smoke", "visual"]
assert len(artifact["flows"]) == 1
assert artifact["flows"][0]["status"] == "pass"
assert len(open(sys.argv[2]).read().splitlines()) == 1
assert set(artifact["legacy_adapter"]["checks"]) == {"browser-smoke", "visual", "behavior"}
audit_dir = Path(sys.argv[1]).parent
derived = [json.load(open(audit_dir / f"{name}.json")) for name in ("browser-smoke", "visual", "behavior")]
assert {item["browser_batch_digest"] for item in derived} == {artifact["batch_digest"]}
assert all(item["implementation_commit"] == artifact["implementation_commit"] for item in derived)
assert derived[0]["active_browser_smoke"] is True
PY
  then
    _fail "browser batch artifact or invocation count mismatch"
    cat "$audit" >&2
  else
    pass_test
  fi
  rm -f /tmp/browser-acceptance.$$ /tmp/browser-acceptance.err.$$
  rm -rf "$t"
}

test_manifest_cannot_claim_behavior_without_interaction() {
  start_test "browser-acceptance: behavior claim requires interaction and later assertion"
  local t module manifest audit fake
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-browser-acceptance-invalid.XXXXXX")
  module="$t/docs/modules/licenses"
  manifest="$t/manifest.json"
  audit="$t/audits/browser-acceptance.json"
  fake="$t/fake-browse"
  mkdir -p "$module"
  cat > "$module/.work-meta.json" <<'JSON'
{"build":{"contract_version":4,"implementation_commit":"abc123","approved_source_hash":"source123","finalization":{"requested_at":"2026-08-06T10:00:00+08:00","requested_commit":"abc123"}}}
JSON
  cat > "$manifest" <<'JSON'
{"schema_version":1,"base_url":"http://127.0.0.1:3000","flows":[{"id":"fake","route":"/ops/licenses","covers":["smoke","visual","behavior"],"commands":[["goto","{base_url}/ops/licenses"],["wait","main"],["screenshot","{audit_dir}/fake.png"]]}]}
JSON
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake"
  chmod +x "$fake"
  if python3 "$RUNNER" --repo-root "$t" --module-dir "$module" --manifest "$manifest" \
    --audit "$audit" --browse-bin "$fake" >/tmp/browser-acceptance.$$ 2>/tmp/browser-acceptance.err.$$; then
    _fail "behavior without interaction must be rejected"
  elif grep -q "交互后的主动断言" /tmp/browser-acceptance.err.$$; then
    pass_test
  else
    _fail "invalid behavior guidance mismatch"
    cat /tmp/browser-acceptance.err.$$ >&2
  fi
  rm -f /tmp/browser-acceptance.$$ /tmp/browser-acceptance.err.$$
  rm -rf "$t"
}

test_legacy_batch_validator_supports_partial_contract_and_rejects_tampering() {
  start_test "browser-acceptance: legacy adapter maps exact required checks and verifies batch digest"
  local t
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-browser-legacy-validator.XXXXXX")
  mkdir -p "$t/.pm-workflow/audits/demo" "$t/docs/modules/demo"
  if PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 - "$t" <<'PY'
import json
import sys
from pathlib import Path

from _lib import build_evidence
from _lib.browser_evidence import browser_batch_digest

root = Path(sys.argv[1])
audit_dir = root / ".pm-workflow/audits/demo"
module_dir = root / "docs/modules/demo"
batch_path = audit_dir / "browser-acceptance.json"
derived_path = audit_dir / "browser-smoke.json"
batch = {
    "schema_version": 1,
    "check": "browser-acceptance",
    "status": "pass",
    "implementation_commit": "commit-1",
    "source_hash": "source-1",
    "active_browser_smoke": True,
    "single_chain_invocation": True,
    "covers": ["behavior", "smoke", "visual"],
    "flows": [{"id": "home", "route": "/", "covers": ["smoke"], "status": "pass"}],
    "exit_code": 0,
    "visual_artifacts": [],
    "missing_visual_artifacts": [],
    "legacy_adapter": {"checks": ["browser-smoke"]},
}
batch["batch_digest"] = browser_batch_digest(batch)
derived = {
    "schema_version": 1,
    "check": "browser-smoke",
    "status": "pass",
    "implementation_commit": "commit-1",
    "source_hash": "source-1",
    "active_browser_smoke": True,
    "single_chain_invocation": True,
    "covers": ["smoke"],
    "flows": [{"id": "home", "route": "/", "status": "pass"}],
    "derived_from": batch_path.name,
    "browser_batch_digest": batch["batch_digest"],
}
batch_path.write_text(json.dumps(batch), encoding="utf-8")
derived_path.write_text(json.dumps(derived), encoding="utf-8")
build = {
    "approved_source_hash": "source-1",
    "implementation_commit": "commit-1",
    "acceptance": {"evidence": [{
        "name": "browser-smoke", "status": "pass", "source_hash": "source-1",
        "commit": "commit-1", "checked_at": "now",
        "artifact": str(derived_path.relative_to(root)),
    }]},
}
build_evidence.canonical_final_checks = lambda meta: ["browser-smoke"]
build_evidence.validate_fresh_evidence(module_dir, build)
batch["flows"][0]["route"] = "/tampered"
batch_path.write_text(json.dumps(batch), encoding="utf-8")
try:
    build_evidence.validate_fresh_evidence(module_dir, build)
except SystemExit as exc:
    assert "摘要不一致" in str(exc)
else:
    raise AssertionError("tampered browser batch should fail")
PY
  then
    pass_test
  else
    _fail "partial legacy browser validation or tamper gate failed"
  fi
  rm -rf "$t"
}

test_browser_flows_run_in_one_chain_and_one_artifact
test_manifest_cannot_claim_behavior_without_interaction
test_legacy_batch_validator_supports_partial_contract_and_rejects_tampering
report_results "browser-acceptance"
