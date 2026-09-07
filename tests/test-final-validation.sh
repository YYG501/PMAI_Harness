#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATION="$FRAMEWORK_ROOT/scripts/final-validation.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"

test_final_validation_isolated_from_active_worktree() {
  start_test "final-validation: frozen commit runs in detached worktree without polluting active dev state"
  local t module audit commit
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-final-validation-test.XXXXXX")
  module="$t/docs/modules/demo"
  audit="$t/.pm-workflow/audits/demo/final-validation.json"
  mkdir -p "$module" "$t/src"
  echo "# demo" > "$module/spec.md"
  echo "tracked" > "$t/tracked.txt"
  python3 "$PROJECT_DEFINITION" write "$t" \
    --source docs/modules/demo/spec.md --type prototype --root . --entrypoint src \
    --language typescript --runtime node --framework nextjs --package-manager pnpm \
    --typecheck-command "test -f tracked.txt" \
    --build-command "touch validation-build.out" >/dev/null
  cat > "$module/.work-meta.json" <<'JSON'
{"build":{"contract_version":4,"implementation_commit":"pending","approved_source_hash":"source-v1","finalization":{"requested_at":null,"requested_commit":null}}}
JSON
  git -C "$t" init -q
  git -C "$t" config user.email "pmai@example.test"
  git -C "$t" config user.name "PMAI Test"
  git -C "$t" add .
  git -C "$t" commit -qm "fixture"
  commit=$(git -C "$t" rev-parse HEAD)
  python3 - "$module/.work-meta.json" "$commit" <<'PY'
import json, sys
path, commit = sys.argv[1:]
data = json.load(open(path))
data["build"]["implementation_commit"] = commit
json.dump(data, open(path, "w"))
PY

  if python3 "$VALIDATION" --repo-root "$t" --module-dir "$module" --audit "$audit" \
    --check typecheck --check build >/tmp/final-validation.$$ 2>/tmp/final-validation.err.$$; then
    _fail "validation must not run before PM requests finalization"
    rm -rf "$t"; return
  elif ! grep -q "PM 尚未请求定稿" /tmp/final-validation.err.$$; then
    _fail "missing PM finalization guidance"
    cat /tmp/final-validation.err.$$ >&2
    rm -rf "$t"; return
  fi

  python3 - "$module/.work-meta.json" "$commit" <<'PY'
import json, sys
path, commit = sys.argv[1:]
data = json.load(open(path))
data["build"]["finalization"] = {
    "requested_at": "2026-07-17T10:00:00+08:00",
    "requested_commit": commit,
    "rebound_at": None,
}
json.dump(data, open(path, "w"))
PY
  if ! python3 "$VALIDATION" --repo-root "$t" --module-dir "$module" --audit "$audit" \
    --check typecheck --check build >/tmp/final-validation.$$ 2>/tmp/final-validation.err.$$; then
    _fail "isolated final validation should pass"
    cat /tmp/final-validation.err.$$ >&2
    rm -rf "$t"; return
  fi
  if [ -e "$t/validation-build.out" ]; then
    _fail "production build artifact leaked into active worktree"
    rm -rf "$t"; return
  fi
  if ! python3 - "$audit" "$commit" <<'PY'
import json, os, sys
artifact = json.load(open(sys.argv[1]))
assert artifact["status"] == "pass"
assert artifact["implementation_commit"] == sys.argv[2]
assert artifact["source_hash"] == "source-v1"
assert artifact["active_worktree_untouched"] is True
assert artifact["cleanup"]["status"] == "complete"
assert not os.path.exists(artifact["validation_worktree"])
assert [item["name"] for item in artifact["commands"]] == ["typecheck", "build"]
assert all(item["status"] == "pass" for item in artifact["commands"])
PY
  then
    _fail "final validation artifact mismatch"
    cat "$audit" >&2
    rm -rf "$t"; return
  fi
  pass_test
  rm -f /tmp/final-validation.$$ /tmp/final-validation.err.$$
  rm -rf "$t"
}

test_root_relative_verification_commands_fallback_to_repo_root() {
  start_test "final-validation: root-relative verification paths run from repository root"
  local t module audit commit
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-final-validation-root-relative.XXXXXX")
  module="$t/docs/modules/demo"
  audit="$t/.pm-workflow/audits/demo/final-validation.json"
  mkdir -p "$module" "$t/app" "$t/tests"
  printf '# demo\n' > "$module/spec.md"
  printf 'value = True\n' > "$t/app/main.py"
  printf 'import unittest\nclass RootRelative(unittest.TestCase):\n    def test_root_relative(self):\n        self.assertTrue(True)\n' > "$t/tests/test_root_relative.py"
  touch "$t/tests/__init__.py"
  python3 "$PROJECT_DEFINITION" write "$t" \
    --source docs/modules/demo/spec.md --type product --root app --entrypoint app/main.py \
    --language python --runtime python3 --framework stdlib --package-manager none \
    --test-command "python3 -m unittest discover -s tests" \
    --build-command "python3 -m py_compile app/main.py" >/dev/null
  cat > "$module/.work-meta.json" <<'JSON'
{"build":{"contract_version":4,"implementation_commit":"pending","approved_source_hash":"source-v1","finalization":{"requested_at":"2026-07-17T10:00:00+08:00","requested_commit":"pending"}}}
JSON
  git -C "$t" init -q
  git -C "$t" config user.email "pmai@example.com"
  git -C "$t" config user.name "PMAI Test"
  git -C "$t" add .
  git -C "$t" commit -qm "fixture"
  commit=$(git -C "$t" rev-parse HEAD)
  python3 - "$module/.work-meta.json" "$commit" <<'PY'
import json, sys
path, commit = sys.argv[1:]
data = json.load(open(path))
data["build"]["implementation_commit"] = commit
data["build"]["finalization"]["requested_commit"] = commit
json.dump(data, open(path, "w"))
PY
  if ! PYTHONPYCACHEPREFIX="$t/.pycache" python3 "$VALIDATION" \
    --repo-root "$t" --module-dir "$module" --audit "$audit" \
    --check test --check build >/tmp/final-validation.$$ 2>/tmp/final-validation.err.$$; then
    _fail "root-relative verification commands should pass"
    cat /tmp/final-validation.err.$$ "$audit" >&2
  elif python3 - "$audit" "$t" <<'PY'
import json, sys
from pathlib import Path
artifact = json.load(open(sys.argv[1]))
assert artifact["status"] == "pass"
validation_root = Path(artifact["validation_worktree"]).resolve()
assert all(Path(item["working_directory"]).resolve() == validation_root for item in artifact["commands"])
PY
  then
    pass_test
  else
    _fail "root-relative command working directory was not recorded"
    cat "$audit" >&2
  fi
  rm -f /tmp/final-validation.$$ /tmp/final-validation.err.$$
  rm -rf "$t"
}

test_subdirectory_root_and_identical_command_dedupe() {
  start_test "final-validation: subdirectory root is cwd and identical checks run once"
  local t module audit commit
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-final-validation-subdir.XXXXXX")
  module="$t/docs/modules/demo"
  audit="$t/.pm-workflow/audits/demo/final-validation.json"
  mkdir -p "$module" "$t/prototypes/src"
  echo "# demo" > "$module/spec.md"
  echo '{}' > "$t/prototypes/package.json"
  python3 "$PROJECT_DEFINITION" write "$t" \
    --source docs/modules/demo/spec.md --type prototype \
    --root prototypes --entrypoint prototypes/src \
    --language typescript --runtime node --framework nextjs --package-manager pnpm \
    --test-command "test -f package.json" \
    --typecheck-command "test -f package.json" \
    --build-command "test -f package.json" >/dev/null
  cat > "$module/.work-meta.json" <<'JSON'
{"build":{"contract_version":4,"implementation_commit":"pending","approved_source_hash":"source-v1","finalization":{"requested_at":"2026-07-17T10:00:00+08:00","requested_commit":"pending"}}}
JSON
  git -C "$t" init -q
  git -C "$t" config user.email "pmai@example.test"
  git -C "$t" config user.name "PMAI Test"
  git -C "$t" add .
  git -C "$t" commit -qm "fixture"
  commit=$(git -C "$t" rev-parse HEAD)
  python3 - "$module/.work-meta.json" "$commit" <<'PY'
import json, sys
path, commit = sys.argv[1:]
data = json.load(open(path))
data["build"]["implementation_commit"] = commit
data["build"]["finalization"]["requested_commit"] = commit
json.dump(data, open(path, "w"))
PY

  if ! python3 "$VALIDATION" --repo-root "$t" --module-dir "$module" --audit "$audit" \
    >/tmp/final-validation.$$ 2>/tmp/final-validation.err.$$; then
    _fail "subdirectory validation should pass"
    cat /tmp/final-validation.err.$$ >&2
  elif ! python3 - "$audit" <<'PY'
import json, sys
artifact = json.load(open(sys.argv[1]))
assert artifact["implementation_root"] == "prototypes"
assert artifact["requested_checks"] == ["test", "typecheck", "build"]
assert len(artifact["commands"]) == 1
assert artifact["commands"][0]["satisfies"] == ["test", "typecheck", "build"]
PY
  then
    _fail "cwd or exact-command dedupe artifact mismatch"
    cat "$audit" >&2
  else
    pass_test
  fi
  rm -f /tmp/final-validation.$$ /tmp/final-validation.err.$$
  rm -rf "$t"
}

test_failures_are_itemized_and_build_still_runs() {
  start_test "final-validation: test/typecheck failures remain raw while build still runs"
  local t module audit commit
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-final-validation-items.XXXXXX")
  module="$t/docs/modules/demo"
  audit="$t/.pm-workflow/audits/demo/final-validation.json"
  mkdir -p "$module" "$t/src"
  echo "# demo" > "$module/spec.md"
  echo "export const ok = true" > "$t/src/app.ts"
  python3 "$PROJECT_DEFINITION" write "$t" \
    --source docs/modules/demo/spec.md --type product --root . --entrypoint src \
    --language typescript --runtime node --framework test --package-manager none \
    --test-command "bash -c 'exit 2'" \
    --typecheck-command "bash -c 'exit 3'" \
    --build-command "test -f src/app.ts" >/dev/null
  cat > "$module/.work-meta.json" <<'JSON'
{"build":{"contract_version":4,"implementation_commit":"pending","approved_source_hash":"source-v1","finalization":{"requested_at":"2026-07-17T10:00:00+08:00","requested_commit":"pending"}}}
JSON
  git -C "$t" init -q
  git -C "$t" config user.email "pmai@example.test"
  git -C "$t" config user.name "PMAI Test"
  git -C "$t" add .
  git -C "$t" commit -qm fixture
  commit=$(git -C "$t" rev-parse HEAD)
  python3 - "$module/.work-meta.json" "$commit" <<'PY'
import json, sys
path, commit = sys.argv[1:]
data = json.load(open(path))
data["build"]["implementation_commit"] = commit
data["build"]["finalization"]["requested_commit"] = commit
json.dump(data, open(path, "w"))
PY
  python3 "$VALIDATION" --repo-root "$t" --module-dir "$module" --audit "$audit" \
    >/tmp/final-validation.$$ 2>/tmp/final-validation.err.$$
  local rc=$?
  if [ "$rc" = "1" ] && python3 - "$audit" <<'PY'
import json, re, sys
artifact = json.load(open(sys.argv[1]))
by_name = {item["name"]: item for item in artifact["commands"]}
assert artifact["schema_version"] == 2
assert artifact["status"] == "fail"
assert by_name["test"]["status"] == "fail" and by_name["test"]["exit_code"] == 2
assert by_name["typecheck"]["status"] == "fail" and by_name["typecheck"]["exit_code"] == 3
assert by_name["build"]["status"] == "pass" and by_name["build"]["exit_code"] == 0
assert re.fullmatch(r"[0-9a-f]{64}", artifact["results_digest"])
PY
  then
    pass_test
  else
    _fail "per-check failure artifact mismatch: rc=$rc"
    cat "$audit" >&2
  fi
  rm -f /tmp/final-validation.$$ /tmp/final-validation.err.$$
  rm -rf "$t"
}

test_legacy_root_command_adapter_is_explicit() {
  start_test "final-validation: recovered legacy build strips one exact duplicate root prefix"
  local t module audit commit source_hash
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-final-validation-legacy-root.XXXXXX")
  module="$t/docs/modules/demo"
  audit="$t/.pm-workflow/audits/demo/final-validation.json"
  mkdir -p "$module" "$t/prototype/src" "$t/.pm-workflow"
  echo "# demo" > "$module/spec.md"
  echo "ok" > "$t/prototype/package.json"
  cat > "$t/.pm-workflow/project.yml" <<'YAML'
schema_version: 1
definition:
  source: docs/modules/demo/spec.md
  source_hash: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  design_revision: 1
  decided_at: 2026-07-17T10:00:00+08:00
project:
  type: prototype
implementation:
  root: prototype
  entrypoints:
    - prototype/src
  stack:
    language: typescript
    runtime: node
    framework: test
    package_manager: pnpm
commands:
  build: cd prototype && test -f package.json
web:
  enabled: false
YAML
  git -C "$t" init -q
  git -C "$t" config user.email "pmai@example.test"
  git -C "$t" config user.name "PMAI Test"
  git -C "$t" add .
  git -C "$t" commit -qm checkpoint
  commit=$(git -C "$t" rev-parse HEAD)
  source_hash=$(printf 'b%.0s' {1..64})
  python3 - "$module/.work-meta.json" "$commit" "$source_hash" <<'PY'
import json, sys
path, commit, source_hash = sys.argv[1:]
meta = {
  "status": "active", "lifecycle_state": "iterating", "approved_source_hash": source_hash,
  "build": {"contract_version": 4, "lifecycle_state": "iterating", "implementation_commit": commit,
    "approved_source_hash": source_hash, "accepted_deltas": [],
    "finalization": {"requested_at": "2026-07-17T10:00:00+08:00", "requested_commit": commit}},
  "legacy_recovery": {"schema_version": 1, "kind": "active-build", "status": "accepted",
    "confirmed_by": "PM", "confirmed_at": "2026-07-17T09:00:00+08:00", "reason": "resume",
    "checkpoint_commit": commit, "authority_source_hash": source_hash,
    "authority_source_scope": ["docs/modules/demo/spec.md"],
    "authority_source_file_hashes": {"docs/modules/demo/spec.md": "c" * 64},
    "original_design_approved_source_hash": source_hash,
    "original_build_approved_source_hash": source_hash,
    "original_replayed_build_approved_source_hash": source_hash,
    "original_hash_chain_state": "consistent", "reconciled_build_approved_source_hash": source_hash,
    "original_contract_version": 4, "original_accepted_delta_count": 0, "original_accepted_deltas": []}}
json.dump(meta, open(path, "w"))
PY
  git -C "$t" add "$module/.work-meta.json"
  git -C "$t" commit -qm contract
  # The bound implementation is the checkpoint containing project.yml and package.json.
  python3 "$VALIDATION" --repo-root "$t" --module-dir "$module" --audit "$audit" \
    --check build >/tmp/final-validation.$$ 2>/tmp/final-validation.err.$$
  local rc=$?
  if [ "$rc" = "0" ] && python3 - "$audit" <<'PY'
import json, sys
artifact = json.load(open(sys.argv[1]))
compat = artifact["compatibility"]
assert compat["legacy_root_command_adapter"] is True
assert compat["adapted_commands"][0]["original"] == "cd prototype && test -f package.json"
assert artifact["commands"][0]["command"] == "test -f package.json"
PY
  then
    pass_test
  else
    _fail "legacy root adapter mismatch: rc=$rc"
    cat /tmp/final-validation.err.$$ "$audit" >&2
  fi
  rm -f /tmp/final-validation.$$ /tmp/final-validation.err.$$
  rm -rf "$t"
}

test_final_validation_isolated_from_active_worktree
test_root_relative_verification_commands_fallback_to_repo_root
test_subdirectory_root_and_identical_command_dedupe
test_failures_are_itemized_and_build_still_runs
test_legacy_root_command_adapter_is_explicit
report_results "final-validation"
