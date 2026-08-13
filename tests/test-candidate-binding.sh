#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-candidate-binding.XXXXXX")
  mkdir -p "$T/prototype"
  printf 'one\n' > "$T/prototype/app.txt"
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  git -C "$T" add -A
  git -C "$T" commit -qm base
  BASE=$(git -C "$T" rev-parse HEAD)
  printf 'two\n' > "$T/prototype/app.txt"
  git -C "$T" add -A
  git -C "$T" commit -qm implementation
  IMPLEMENTATION=$(git -C "$T" rev-parse HEAD)
}

teardown_fixture() { rm -rf "$T"; }

binding_json() {
  PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 - "$T" "$BASE" "$IMPLEMENTATION" "$@" <<'PY'
import json, sys
from pathlib import Path
from _lib.candidate_binding import select_candidate
root = Path(sys.argv[1])
base, implementation = sys.argv[2:4]
mode = sys.argv[4]
build = {
    "baseline_sha": base,
    "implementation_commit": implementation if mode != "unrecorded" else None,
    "approved_source_hash": "a" * 64,
    "target": {"paths": ["prototype/app.txt"]},
}
recovery = None
if mode.startswith("legacy"):
    recovery = {"kind": "active-build", "checkpoint_commit": implementation}
print(json.dumps(select_candidate(root, build, recovery)))
PY
}

test_new_candidate_uses_head() {
  start_test "candidate binding: new build binds current HEAD"
  setup_fixture
  local out
  out=$(binding_json unrecorded)
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["source_kind"]=="current-head"; assert d["source_commit"]==sys.argv[1]; assert d["diff_mode"]=="commit-range"' "$IMPLEMENTATION" <<<"$out"; then
    pass_test
  else
    _fail "new candidate binding mismatch: $out"
  fi
  teardown_fixture
}

test_unrelated_head_keeps_recorded_candidate() {
  start_test "candidate binding: unrelated later commit does not replace recorded target tree"
  setup_fixture
  printf 'unrelated\n' > "$T/notes.txt"
  git -C "$T" add -A
  git -C "$T" commit -qm unrelated
  local out
  out=$(binding_json recorded)
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["source_kind"]=="recorded-implementation"; assert d["source_commit"]==sys.argv[1]' "$IMPLEMENTATION" <<<"$out"; then
    pass_test
  else
    _fail "unrelated HEAD should preserve recorded implementation: $out"
  fi
  teardown_fixture
}

test_changed_target_advances_to_head() {
  start_test "candidate binding: changed approved target advances to current HEAD"
  setup_fixture
  printf 'three\n' > "$T/prototype/app.txt"
  git -C "$T" add -A
  git -C "$T" commit -qm next-implementation
  local head out
  head=$(git -C "$T" rev-parse HEAD)
  out=$(binding_json recorded)
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["source_kind"]=="current-head"; assert d["source_commit"]==sys.argv[1]' "$head" <<<"$out"; then
    pass_test
  else
    _fail "target change should select HEAD: $out"
  fi
  teardown_fixture
}

test_legacy_recovery_ignores_unrelated_head() {
  start_test "candidate binding: legacy recovery binds checkpoint across unrelated commits"
  setup_fixture
  printf 'unrelated\n' > "$T/notes.txt"
  git -C "$T" add -A
  git -C "$T" commit -qm unrelated
  local out
  out=$(binding_json legacy)
  if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["source_kind"]=="legacy-recovery-checkpoint"; assert d["source_commit"]==d["base_commit"]==sys.argv[1]; assert d["diff_mode"]=="approved-target-snapshot"' "$IMPLEMENTATION" <<<"$out"; then
    pass_test
  else
    _fail "legacy checkpoint binding mismatch: $out"
  fi
  teardown_fixture
}

test_binding_digest_rejects_tampering() {
  start_test "candidate binding: digest rejects tampered stable fields"
  setup_fixture
  if PYTHONPATH="$FRAMEWORK_ROOT/scripts" python3 - "$T" "$BASE" "$IMPLEMENTATION" <<'PY'
import sys
from pathlib import Path
from _lib.candidate_binding import select_candidate, validate_candidate_binding

root = Path(sys.argv[1])
build = {
    "baseline_sha": sys.argv[2],
    "implementation_commit": sys.argv[3],
    "approved_source_hash": "a" * 64,
    "target": {"paths": ["prototype/app.txt"]},
}
build["candidate_binding"] = select_candidate(root, build)
validate_candidate_binding(root, build)
build["candidate_binding"]["source_kind"] = "tampered"
try:
    validate_candidate_binding(root, build)
except ValueError as exc:
    assert "binding_digest" in str(exc)
else:
    raise AssertionError("tampered binding should fail")
PY
  then
    pass_test
  else
    _fail "candidate binding digest did not fail closed"
  fi
  teardown_fixture
}

test_new_candidate_uses_head
test_unrelated_head_keeps_recorded_candidate
test_changed_target_advances_to_head
test_legacy_recovery_ignores_unrelated_head
test_binding_digest_rejects_tampering
report_results "candidate-binding"
