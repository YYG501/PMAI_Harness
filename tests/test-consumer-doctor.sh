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

make_layout_unversioned() {
  local repo="$1" replacement
  replacement="${repo%/}/.pm-workflow/config.yml.unversioned"
  sed -n '/^builder:/,$p' "$repo/.pm-workflow/config.yml" > "$replacement" \
    && mv "$replacement" "$repo/.pm-workflow/config.yml"
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

test_ready_contract_gap_is_progress_only() {
  start_test "consumer-doctor: incomplete ready scope is progress guidance, not repository damage"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-ready-gap"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  python3 - "$repo/docs/modules/demo/.work-meta.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    payload = json.load(handle)
payload.pop("approved_target", None)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  out=$(audit "$repo") || { _fail "ready gap audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
finding = next(item for item in payload["findings"] if item["code"] == "ready_target_missing")
assert payload["status"] == "current"
assert finding["level"] == "warning"
assert finding["kind"] == "project_advisory"
assert finding["blocking"] is False
PY
  then
    pass_test
  else
    _fail "an incomplete ready scope should only block that module from starting"
    echo "$out" >&2
  fi
}

test_unknown_module_file_is_not_mislabeled_as_a_spec() {
  start_test "consumer-doctor: unknown module files are reported once without calling them specs"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  printf 'finder metadata\n' > "$repo/docs/modules/.DS_Store"
  out=$(audit "$repo") || { _fail "unknown module file audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
findings = [item for item in payload["findings"] if item.get("path") == "docs/modules/.DS_Store"]
assert [item["code"] for item in findings] == ["modules_unknown_file"]
PY
  then
    pass_test
  else
    _fail "an unknown file should not also be called an untracked functional spec"
    echo "$out" >&2
  fi
}

test_stale_consumer_entry_is_machine_detectable() {
  start_test "consumer-doctor: old AGENTS startup rule is detected without rewriting it"
  local repo before after out entry_out missing_out rc
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sed 's/install-project-hooks\.sh/install-codex-hooks.sh/g; s/ --check//g' \
    "$repo/AGENTS.md" > "$repo/AGENTS.md.old" \
    && mv "$repo/AGENTS.md.old" "$repo/AGENTS.md"
  before=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  out=$(audit "$repo") || { _fail "stale entry audit failed"; return; }
  entry_out=$(python3 "$CHECKER" --repo-root "$repo" --entry-only)
  rc=$?
  after=$(git -C "$repo" status --porcelain=v1 --untracked-files=all)
  if [ "$rc" != "1" ] || [ "$before" != "$after" ] || ! python3 - "$out" "$entry_out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
entry = json.loads(sys.argv[2])
assert payload["status"] == "sync_required"
assert entry["status"] == "stale"
assert "host_rules_stale" in {item["code"] for item in payload["findings"]}
PY
  then
    _fail "old startup rules should be reported by the shared read-only check"
    echo "$out" >&2
    echo "$entry_out" >&2
    return
  fi
  rm "$repo/AGENTS.md"
  missing_out=$(python3 "$CHECKER" --repo-root "$repo" --entry-only)
  rc=$?
  if [ "$rc" != "2" ] || ! python3 - "$missing_out" <<'PY'
import json
import sys

assert json.loads(sys.argv[1])["status"] == "missing"
PY
  then
    _fail "missing AGENTS.md should be distinct from an outdated startup rule"
    echo "$missing_out" >&2
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

test_unversioned_legacy_module_formats_are_not_invalid() {
  start_test "consumer-doctor: unversioned spec+decisions and merged spec are compatibility findings"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  make_layout_unversioned "$repo" || { _fail "unable to remove layout contract"; return; }
  mkdir -p "$repo/docs/modules/legacy-pair" "$repo/docs/modules/merged-spec"
  printf '# Legacy pair spec\nExisting product rules.\n' > "$repo/docs/modules/legacy-pair/spec.md"
  printf '# Legacy pair decisions\nDecision history.\n' > "$repo/docs/modules/legacy-pair/decisions.md"
  printf '# Merged legacy spec\nDiscussion, decisions, and specification are intentionally merged.\n' \
    > "$repo/docs/modules/merged-spec/spec.md"
  printf '\n- legacy-pair\n- merged-spec\n' >> "$repo/docs/modules/INDEX.md"
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  out=$(audit "$repo") || { _fail "legacy audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
findings = payload["findings"]
assert payload["status"] == "sync_required"
assert payload["classification_summary"]["project_content_invalid"] == 0
assert sum(item["code"] == "legacy_module_inferred" for item in findings) == 2
assert not any(item["code"] == "module_document_missing" for item in findings)
assert all(not item["blocking"] for item in findings)
PY
  then
    pass_test
  else
    _fail "bounded legacy inference should request declaration without invalidating content"
    echo "$out" >&2
  fi
}

test_declared_retired_and_split_modules_follow_truth_sources() {
  start_test "consumer-doctor: declared retired/split modules point to tracked substantive truth sources"
  local repo current broken out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  mkdir -p "$repo/docs/modules/retired-module" "$repo/docs/modules/split-module"
  printf '# Successor specification\nCurrent product truth.\n' > "$repo/docs/modules/successor.md"
  printf '\n| [`successor.md`](successor.md) | 功能规格 | successor | current truth |\n' \
    >> "$repo/docs/modules/INDEX.md"
  cat > "$repo/.pm-workflow/config.yml" <<'YAML'
consumer:
  schema_version: 1
  layout_version: 1
  paths:
    archive: docs/archive
  compatibility:
    module_retired:
      path: docs/modules/retired-module
      state: retired
      truth_sources:
        - docs/modules/successor.md
    module_split:
      path: docs/modules/split-module
      state: split
      truth_sources:
        - docs/modules/successor.md
builder:
  profiles:
    fixture:
      executor: manual
YAML
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  current=$(audit "$repo") || { _fail "declared compatibility audit failed"; return; }
  printf '   \n<!-- placeholder only -->\n' > "$repo/docs/modules/successor.md"
  broken=$(audit "$repo") || { _fail "broken successor audit failed"; return; }
  if python3 - "$current" "$broken" <<'PY'
import json
import sys

current, broken = (json.loads(value) for value in sys.argv[1:])
assert current["status"] == "current"
assert current["classification_summary"]["legacy_compatible"] == 2
assert not any(item["blocking"] for item in current["findings"])
assert broken["status"] == "invalid"
assert "module_truth_source_blank" in {item["code"] for item in broken["findings"]}
PY
  then
    pass_test
  else
    _fail "retired/split truth source validation mismatch"
    echo "$current" >&2
    echo "$broken" >&2
  fi
}

test_nonempty_inputs_do_not_require_gitkeep() {
  start_test "consumer-doctor: nonempty inputs do not require .gitkeep"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  rm -f "$repo/docs/inputs/.gitkeep"
  printf '# Source material\nReal input.\n' > "$repo/docs/inputs/source.md"
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  out=$(audit "$repo") || { _fail "inputs audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "current"
assert not any("gitkeep" in str(item.get("path", "")) for item in payload["findings"])
PY
  then
    pass_test
  else
    _fail "nonempty inputs should not depend on a sentinel file"
  fi
}

test_standard_index_can_register_legacy_index_and_custom_archive() {
  start_test "consumer-doctor: INDEX.md remains standard while registering legacy index and custom archive"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  git -C "$repo" mv docs/archive docs/_归档
  sed 's#archive: docs/archive#archive: docs/_归档#' "$repo/.pm-workflow/config.yml" \
    > "$repo/.pm-workflow/config.yml.tmp" \
    && mv "$repo/.pm-workflow/config.yml.tmp" "$repo/.pm-workflow/config.yml"
  sed 's#`archive/`#`_归档/`#' "$repo/docs/INDEX.md" > "$repo/docs/INDEX.md.tmp" \
    && mv "$repo/docs/INDEX.md.tmp" "$repo/docs/INDEX.md"
  printf '\n- [`索引.md`](./索引.md) — 历史项目索引，保留既有引用。\n' >> "$repo/docs/INDEX.md"
  printf '# 历史项目索引\nExisting navigation.\n' > "$repo/docs/索引.md"
  commit_fixture "$repo" || { _fail "fixture commit failed"; return; }
  out=$(audit "$repo") || { _fail "custom layout audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "current"
assert payload["consumer_contract"]["archive"] == "docs/_归档"
assert not any(item.get("path") == "docs/索引.md" for item in payload["findings"])
assert not any(item.get("path") == "docs/archive" for item in payload["findings"])
PY
  then
    pass_test
  else
    _fail "standard index registration or custom archive contract regressed"
    echo "$out" >&2
  fi
}

test_framework_sync_does_not_hide_project_damage() {
  start_test "consumer-doctor: framework-managed sync does not hide missing product spine"
  local repo out
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  rm -f "$repo/PRODUCT.md" "$repo/docs/engineering/INDEX.md"
  out=$(audit "$repo") || { _fail "mixed finding audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
kinds = {item["kind"] for item in payload["findings"]}
assert payload["status"] == "invalid"
assert "project_content_invalid" in kinds
assert "framework_managed_sync" in kinds
assert any(item["blocking"] for item in payload["findings"])
PY
  then
    pass_test
  else
    _fail "blocking project damage should win over sync findings"
  fi
}

test_active_lifecycle_missing_document_is_invalid() {
  start_test "consumer-doctor: compatibility cannot downgrade active lifecycle validation"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-active-doc"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  sed 's/^  compatibility: {}$/  compatibility:\n    module_demo:\n      path: docs\/modules\/demo\n      state: legacy\n      format: merged_spec/' \
    "$repo/.pm-workflow/config.yml" > "$repo/.pm-workflow/config.yml.tmp" \
    && mv "$repo/.pm-workflow/config.yml.tmp" "$repo/.pm-workflow/config.yml"
  rm -f "$repo/docs/modules/demo/decisions.md"
  out=$(audit "$repo") || { _fail "active document audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid"
assert any(item["code"] == "active_module_compatibility_ignored" for item in payload["findings"])
assert any(
    item["code"] == "module_document_missing"
    and item.get("path", "").endswith("decisions.md")
    and item["blocking"]
    for item in payload["findings"]
)
PY
  then
    pass_test
  else
    _fail "active lifecycle must keep strict document validation"
  fi
}

test_blank_placeholder_document_is_invalid() {
  start_test "consumer-doctor: blank placeholder documents cannot satisfy current contract"
  local repo out sentinel
  repo=$(new_consumer) || { _fail "fixture init failed"; return; }
  sentinel="${repo%/repo}/unused-placeholder"
  prepare_ready_project "$repo" "$sentinel" || { _fail "ready fixture failed"; return; }
  printf '   \n<!-- intentionally blank -->\n' > "$repo/docs/modules/demo/spec.md"
  out=$(audit "$repo") || { _fail "blank document audit failed"; return; }
  if python3 - "$out" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
assert payload["status"] == "invalid"
assert "module_document_blank" in {item["code"] for item in payload["findings"]}
PY
  then
    pass_test
  else
    _fail "blank placeholder should not make doctor green"
  fi
}

test_fresh_consumer_is_current_and_read_only
test_missing_and_misplaced_documents_are_reported
test_project_definition_drives_custom_implementation_location
test_ready_contract_gap_is_progress_only
test_unknown_module_file_is_not_mislabeled_as_a_spec
test_stale_consumer_entry_is_machine_detectable
test_missing_implementation_entrypoint_blocks_build_recovery
test_mockup_manifest_assets_and_board_are_checked
test_secret_config_is_never_echoed
test_legacy_layout_requires_sync_not_structural_repair
test_non_git_and_symlinked_truth_sources_fail_closed
test_active_build_must_match_project_definition
test_unversioned_legacy_module_formats_are_not_invalid
test_declared_retired_and_split_modules_follow_truth_sources
test_nonempty_inputs_do_not_require_gitkeep
test_standard_index_can_register_legacy_index_and_custom_archive
test_framework_sync_does_not_hide_project_damage
test_active_lifecycle_missing_document_is_invalid
test_blank_placeholder_document_is_invalid

report_results "consumer-doctor"
