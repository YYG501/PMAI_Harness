#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_CONTRACT="$FRAMEWORK_ROOT/scripts/build-contract.py"
BOUNDARY="$FRAMEWORK_ROOT/scripts/prototype-boundary.py"
CONTEXT_PACK="$FRAMEWORK_ROOT/scripts/context-pack.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-prototype-boundary.XXXXXX")
  git init -q "$T"
  git -C "$T" config user.email "test@example.com"
  git -C "$T" config user.name "Test"
  MODULE="$T/docs/modules/demo"
  mkdir -p "$MODULE" "$T/prototype"
  write_equivalent_product_baseline "$T"
  echo '# Demo' > "$MODULE/spec.md"
  echo '# Discussion' > "$MODULE/discussion.md"
  echo '# Decisions' > "$MODULE/decisions.md"
  cat > "$MODULE/.work-meta.json" <<'JSON'
{"id":"work-demo","name":"demo","branch":"main","stage":1,"status":"active","lifecycle_state":"designing"}
JSON
  echo '# Prototype' > "$T/prototype/README.md"
  echo 'outside target' > "$T/outside.txt"
  printf '.pm-workflow/context/\n' > "$T/.gitignore"
  python3 "$PROJECT_DEFINITION" write "$T" \
    --source docs/modules/demo/spec.md --type prototype \
    --root prototype --entrypoint prototype \
    --language typescript --runtime node --framework test --package-manager none >/dev/null
  git -C "$T" add -A
  git -C "$T" commit -q -m 'design basis'
  PACK="$T/.pm-workflow/context/demo.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module "$MODULE" --output "$PACK" >/dev/null
  SOURCE_HASH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["source_hash"])' "$PACK")
  CHECKPOINT=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" ready "$MODULE" \
    --approved-source-hash "$SOURCE_HASH" --checkpoint-commit "$CHECKPOINT" \
    --context-pack "$PACK" --target-path prototype --design-revision 1 >/dev/null
  git -C "$T" add docs/modules/demo/.work-meta.json
  git -C "$T" commit -q -m 'mark demo ready'
  BASE=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" start "$MODULE" \
    --anchor docs/modules/demo/spec.md --mode main --executor native --branch main \
    --baseline-sha "$BASE" --target-kind prototype --target-path prototype/ --entrypoint prototype/ \
    --approved-source-hash "$SOURCE_HASH" --required-check prototype-boundary --required-check coverage >/dev/null
  git -C "$T" add docs/modules/demo/.work-meta.json
  git -C "$T" commit -q -m 'start build'
  echo 'export const demo = true' > "$T/prototype/app.ts"
  git -C "$T" add prototype/app.ts
  git -C "$T" commit -q -m 'build prototype'
  IMPLEMENTATION=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" commit "$MODULE" --implementation-commit "$IMPLEMENTATION" >/dev/null
  REPORT="$T/.pm-workflow/audits/demo/prototype-boundary.json"
}

teardown_fixture() {
  rm -rf "$T"
}

test_semantic_review_is_explicit() {
  start_test "prototype-boundary: candidate needs explicit semantic review before pass"
  setup_fixture
  if python3 "$BOUNDARY" "$MODULE" --output "$REPORT" >/tmp/prototype-boundary.$$ 2>/tmp/prototype-boundary.err.$$; then
    _fail "boundary check without semantic confirmation should not pass"
    teardown_fixture; return
  fi
  if ! python3 - "$REPORT" <<'PY'; then
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "needs-review"
assert data["outside_target_paths"] == []
assert data["unapproved_signals"] == []
assert data["semantic_review"]["confirmed_no_real_system_changes"] is False
PY
    _fail "needs-review artifact mismatch"
    teardown_fixture; return
  fi
  if python3 "$BOUNDARY" "$MODULE" --output "$REPORT" \
    --confirm-no-real-system-changes --simulated-capability "数据持久化" \
    >/tmp/prototype-boundary.$$ 2>/tmp/prototype-boundary.err.$$ \
    && python3 - "$REPORT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "pass"
assert data["implementation_mode"] == "interactive-simulation"
assert data["simulated_capabilities"] == ["数据持久化"]
assert data["semantic_review"]["confirmed_no_real_system_changes"] is True
PY
  then
    pass_test
  else
    _fail "confirmed prototype boundary should pass"
    cat /tmp/prototype-boundary.err.$$ >&2
  fi
  rm -f /tmp/prototype-boundary.$$ /tmp/prototype-boundary.err.$$
  teardown_fixture
}

test_database_migration_blocks() {
  start_test "prototype-boundary: database migration signal blocks prototype finalization"
  setup_fixture
  mkdir -p "$T/.pm-workflow/audits/demo"
  echo '{"status":"pass"}' > "$T/.pm-workflow/audits/demo/previous-candidate.json"
  git -C "$T" add .pm-workflow/audits/demo/previous-candidate.json
  git -C "$T" commit -q -m 'record previous candidate audit'
  mkdir -p "$T/prototype/migrations"
  echo 'CREATE TABLE users(id INT);' > "$T/prototype/migrations/001-users.sql"
  git -C "$T" add prototype/migrations/001-users.sql
  git -C "$T" commit -q -m 'add real migration'
  IMPLEMENTATION=$(git -C "$T" rev-parse HEAD)
  python3 "$BUILD_CONTRACT" commit "$MODULE" --implementation-commit "$IMPLEMENTATION" >/dev/null
  if python3 "$BOUNDARY" "$MODULE" --output "$REPORT" --confirm-no-real-system-changes \
    >/tmp/prototype-boundary.$$ 2>/tmp/prototype-boundary.err.$$; then
    _fail "database migration should block prototype boundary"
    teardown_fixture; return
  fi
  if python3 - "$REPORT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["status"] == "blocked"
assert data["outside_target_paths"] == []
assert any(item["category"] == "database-migration" for item in data["unapproved_signals"])
PY
  then
    pass_test
  else
    _fail "database migration block artifact mismatch"
  fi
  rm -f /tmp/prototype-boundary.$$ /tmp/prototype-boundary.err.$$
  teardown_fixture
}

test_deleted_outside_target_blocks() {
  start_test "build-contract: deletion outside approved target blocks iteration commit"
  setup_fixture
  rm "$T/outside.txt"
  git -C "$T" add outside.txt
  git -C "$T" commit -q -m 'delete outside target'
  IMPLEMENTATION=$(git -C "$T" rev-parse HEAD)
  if ! python3 "$BUILD_CONTRACT" commit "$MODULE" --implementation-commit "$IMPLEMENTATION" \
    >/tmp/prototype-boundary.$$ 2>/tmp/prototype-boundary.err.$$ \
    && grep -q "批准范围外路径.*outside.txt" /tmp/prototype-boundary.err.$$; then
    pass_test
  else
    _fail "outside-target deletion should be rejected when recording the iteration commit"
  fi
  rm -f /tmp/prototype-boundary.$$ /tmp/prototype-boundary.err.$$
  teardown_fixture
}

test_semantic_review_is_explicit
test_database_migration_blocks
test_deleted_outside_target_blocks
report_results "prototype-boundary"
