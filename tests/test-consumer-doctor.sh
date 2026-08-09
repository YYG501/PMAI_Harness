#!/usr/bin/env bash
# Read-only consumer topology, document placement, project definition, and mockup checks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECKER="$REPO_ROOT/scripts/consumer-doctor.py"
INIT="$REPO_ROOT/scripts/init-project.sh"
PROJECT_DEFINITION="$REPO_ROOT/scripts/project-definition.py"
MOCK_BOARD="$REPO_ROOT/scripts/gen-mock-board.py"
CLEANUP_ROOT=$(mktemp -d /tmp/pmai-consumer-doctor-suite.XXXXXX)

cleanup() {
  rm -rf -- "$CLEANUP_ROOT"
}
trap cleanup EXIT

new_consumer() {
  local base repo
  base=$(mktemp -d "$CLEANUP_ROOT/fixture.XXXXXX") || return 1
  repo="$base/repo"
  if ! bash "$INIT" DoctorFixture "$repo" "consumer doctor fixture" >/dev/null 2>&1; then
    return 1
  fi
  printf '%s\n' "$repo"
}

audit() {
  python3 "$CHECKER" --repo-root "$1"
}

commit_fixture() {
  local repo="$1"
  git -C "$repo" add -A >/dev/null \
    && git -C "$repo" commit --no-verify -m "test: update fixture" >/dev/null
}

test_fresh_consumer_is_current_and_read_only() {
  start_test "consumer-doctor: fresh init is current and check is read-only"
  local repo before after out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  before=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  out=$(audit "$repo") || { _fail "fresh audit failed"; return; }
  after=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  if [ "$before" != "$after" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "current"
assert payload["phase"] == "initialized"
assert payload["summary"] == {"error": 0, "sync": 0, "warning": 0}
assert payload["project_definition"]["state"] == "absent"
PY
  then
    _fail "fresh consumer should be current and unchanged"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_missing_and_misplaced_documents_are_reported() {
  start_test "consumer-doctor: missing spine and misplaced docs are distinct"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  rm -f "$repo/PRODUCT-RULES.md"
  printf '# loose PRD\n' > "$repo/docs/loose-prd.md"
  out=$(audit "$repo") || { _fail "document audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "missing_required_file" in codes
assert "misplaced_docs_markdown" in codes
PY
  then
    pass_test
  else
    _fail "missing and misplaced documents were not classified"
    echo "$out" >&2
  fi
}

prepare_ready_project() {
  local repo="$1" sentinel="$2"
  mkdir -p "$repo/docs/modules/demo" "$repo/apps/web"
  printf '# Discussion\n' > "$repo/docs/modules/demo/discussion.md"
  printf '# Decisions\n' > "$repo/docs/modules/demo/decisions.md"
  printf '# Spec\n' > "$repo/docs/modules/demo/spec.md"
  printf 'export const demo = true;\n' > "$repo/apps/web/index.ts"
  python3 "$PROJECT_DEFINITION" write "$repo" \
    --source docs/modules/demo/spec.md \
    --type prototype \
    --root apps/web \
    --entrypoint apps/web \
    --language typescript \
    --runtime node \
    --framework nextjs \
    --package-manager pnpm \
    --test-command "touch $sentinel" >/dev/null || return 1
  cat > "$repo/docs/modules/demo/.work-meta.json" <<'JSON'
{
  "id": "work-demo",
  "name": "demo",
  "status": "active",
  "stage": 1,
  "lifecycle_state": "ready_to_build",
  "design_revision": 1,
  "approved_source_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "design_checkpoint_commit": "fixture",
  "approved_target": {"paths": ["apps/web"]}
}
JSON
  commit_fixture "$repo"
}

test_project_definition_drives_custom_implementation_location() {
  start_test "consumer-doctor: project.yml drives implementation location without executing commands"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/command-was-executed"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  printf '# Spec changed without construction plan change\n' > "$repo/docs/modules/demo/spec.md"
  out=$(audit "$repo") || { _fail "project definition audit failed"; return; }
  if [ -e "$sentinel" ] || ! python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "current"
assert payload["phase"] == "ready_to_build"
assert payload["project_definition"]["root"] == "apps/web"
assert payload["project_definition"]["entrypoints"] == ["apps/web"]
assert not any("source_hash" in code for code in codes)
PY
  then
    _fail "custom implementation location or command safety check failed"
    echo "$out" >&2
    return
  fi
  pass_test
}

test_missing_implementation_entrypoint_blocks_build_recovery() {
  start_test "consumer-doctor: missing implementation entrypoint invalidates active build"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  rm -rf "$repo/apps/web"
  cat > "$repo/docs/modules/demo/.work-meta.json" <<'JSON'
{
  "id": "work-demo",
  "name": "demo",
  "status": "active",
  "stage": 1,
  "lifecycle_state": "building",
  "build": {
    "contract_version": 1,
    "lifecycle_state": "building",
    "mode": "main",
    "target": {"kind": "prototype", "paths": ["apps/web"], "entrypoints": ["apps/web"]}
  }
}
JSON
  out=$(audit "$repo") || { _fail "missing implementation audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "implementation_root_invalid" in codes
PY
  then
    pass_test
  else
    _fail "missing implementation root should invalidate active build"
    echo "$out" >&2
  fi
}

prepare_valid_mockups() {
  local repo="$1"
  mkdir -p "$repo/mockups/approach-a"
  printf '<main>Approach A</main>\n' > "$repo/mockups/approach-a/index.html"
  cat > "$repo/mockups/manifest.json" <<'JSON'
{
  "variants": [
    {
      "path": "approach-a/index.html",
      "requirement": "demo",
      "title": "Approach A",
      "explores": "task flow",
      "good_parts": "clear state",
      "status": "活跃",
      "round": "第一轮",
      "featured": false
    }
  ]
}
JSON
  python3 "$MOCK_BOARD" "$repo" >/dev/null || return 1
  commit_fixture "$repo"
}

test_mockup_manifest_assets_and_board_are_checked() {
  start_test "consumer-doctor: mockup manifest paths and generated board stay aligned"
  local repo current stale invalid replacement
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  prepare_valid_mockups "$repo" || { _fail "mockup fixture failed"; return; }
  current=$(audit "$repo") || { _fail "valid mockup audit failed"; return; }
  replacement="$repo/mockups/manifest.json.tmp"
  sed 's/task flow/updated task flow/' "$repo/mockups/manifest.json" > "$replacement" \
    && mv "$replacement" "$repo/mockups/manifest.json" \
    || { _fail "mockup manifest update failed"; return; }
  stale=$(audit "$repo") || { _fail "stale board audit failed"; return; }
  sed 's#approach-a/index.html#../outside.html#' "$repo/mockups/manifest.json" > "$replacement" \
    && mv "$replacement" "$repo/mockups/manifest.json" \
    || { _fail "mockup path update failed"; return; }
  invalid=$(audit "$repo") || { _fail "invalid mockup path audit failed"; return; }
  if python3 - "$current" "$stale" "$invalid" <<'PY'
import json
import sys

current, stale, invalid = (json.loads(value) for value in sys.argv[1:])
assert current["status"] == "current"
assert current["mockups"] == {"state": "current", "variants": 1}
assert "mockup_board_stale" in {item["code"] for item in stale["findings"]}
assert invalid["status"] == "invalid"
assert "mockup_variant_path" in {item["code"] for item in invalid["findings"]}
PY
  then
    pass_test
  else
    _fail "mockup topology findings mismatch"
  fi
}

test_secret_config_is_never_echoed() {
  start_test "consumer-doctor: tracked secret config is blocked without reading or echoing token"
  local repo out token
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  token="PMAI_DOCTOR_SECRET_DO_NOT_PRINT"
  printf '{"prd":{"token":"%s"}}\n' "$token" > "$repo/.claude/lark-publish.json"
  git -C "$repo" add -f .claude/lark-publish.json >/dev/null
  git -C "$repo" commit --no-verify -m "test: tracked secret" >/dev/null
  out=$(audit "$repo") || { _fail "secret audit failed"; return; }
  if [[ "$out" == *"$token"* ]]; then
    _fail "doctor leaked secret config content"
  elif python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid"
assert "secret_config_tracked" in {item["code"] for item in payload["findings"]}
PY
  then
    pass_test
  else
    _fail "tracked secret config was not blocked"
  fi
}

test_legacy_layout_requires_sync_not_structural_repair() {
  start_test "consumer-doctor: legacy task layout is a sync finding"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mkdir -p "$repo/requirements/active"
  out=$(audit "$repo") || { _fail "legacy audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "sync_required"
assert "legacy_layout" in {item["code"] for item in payload["findings"]}
PY
  then
    pass_test
  else
    _fail "legacy layout should request explicit migration"
  fi
}

test_non_git_and_symlinked_truth_sources_fail_closed() {
  start_test "consumer-doctor: non-Git PMAI markers and symlinked truth sources fail closed"
  local base repo non_git symlinked
  base=$(mktemp -d "$CLEANUP_ROOT/non-git.XXXXXX") || { _fail "temp dir failed"; return; }
  printf '# PMAI consumer marker\n' > "$base/PRODUCT-STATE.md"
  non_git=$(audit "$base") || true

  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mv "$repo/PRODUCT.md" "$repo/PRODUCT.real.md"
  ln -s PRODUCT.real.md "$repo/PRODUCT.md"
  symlinked=$(audit "$repo") || true
  if python3 - "$non_git" "$symlinked" <<'PY'
import json
import sys

non_git, symlinked = (json.loads(value) for value in sys.argv[1:])
assert non_git["status"] == "invalid"
assert "not_git_repository" in {item["code"] for item in non_git["findings"]}
assert symlinked["status"] == "invalid"
assert "managed_path_symlink" in {item["code"] for item in symlinked["findings"]}
PY
  then
    pass_test
  else
    _fail "repository identity or symlink boundary did not fail closed"
  fi
}

test_active_build_must_match_project_definition() {
  start_test "consumer-doctor: active build target must match project.yml type and entrypoints"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-mismatch"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  cat > "$repo/docs/modules/demo/.work-meta.json" <<'JSON'
{
  "id": "work-demo",
  "name": "demo",
  "status": "active",
  "stage": 1,
  "lifecycle_state": "building",
  "build": {
    "contract_version": 2,
    "lifecycle_state": "building",
    "mode": "main",
    "executor": "codex",
    "design_revision": 1,
    "approved_source_hash": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "target": {"kind": "product", "paths": ["server/api"], "entrypoints": ["server"]},
    "acceptance": {"required_checks": ["tests"], "evidence": []},
    "docs_status": "pending"
  }
}
JSON
  out=$(audit "$repo") || { _fail "mismatched build audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
codes = {item["code"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "build_project_type_mismatch" in codes
assert "build_entrypoints_mismatch" in codes
assert "build_target_outside_root" in codes
PY
  then
    pass_test
  else
    _fail "active build/project.yml mismatch was not blocked"
    echo "$out" >&2
  fi
}

test_fresh_consumer_is_current_and_read_only
test_missing_and_misplaced_documents_are_reported
test_project_definition_drives_custom_implementation_location
test_missing_implementation_entrypoint_blocks_build_recovery
test_mockup_manifest_assets_and_board_are_checked
test_secret_config_is_never_echoed
test_legacy_layout_requires_sync_not_structural_repair
test_non_git_and_symlinked_truth_sources_fail_closed
test_active_build_must_match_project_definition

report_results "consumer-doctor"
