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

test_final_validation_isolated_from_active_worktree
test_subdirectory_root_and_identical_command_dedupe
report_results "final-validation"
