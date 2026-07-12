#!/usr/bin/env bash
# `.pm-workflow/project.yml` contract and compatibility regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DEFINITION="$REPO_ROOT/scripts/project-definition.py"
PROJECT_TYPE="$REPO_ROOT/scripts/project-type.py"

write_spec() {
  local repo="$1"
  mkdir -p "$repo/docs/modules/demo"
  printf '# Demo\n' > "$repo/docs/modules/demo/spec.md"
}

write_definition() {
  local repo="$1" type="$2"
  shift 2
  python3 "$PROJECT_DEFINITION" write "$repo" \
    --source docs/modules/demo/spec.md \
    --type "$type" \
    --root . \
    --entrypoint app/ \
    --language typescript \
    --runtime node \
    --framework nextjs \
    --package-manager pnpm \
    --build-command "pnpm run build" \
    "$@"
}

test_valid_prototype_and_product() {
  start_test "project-definition: prototype/product valid definitions round-trip"
  local t product prototype
  t=$(mktemp -d)
  write_spec "$t"
  product=$(write_definition "$t" product --web-start "pnpm dev --port {port}" --web-port 3000) || {
    _fail "product definition should write"
    rm -rf "$t"
    return
  }
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["project"]["type"]=="product"; assert d["web"]["enabled"] is True' <<<"$product" || {
    _fail "product definition output mismatch"
    rm -rf "$t"
    return
  }
  rm -f "$t/.pm-workflow/project.yml"
  prototype=$(write_definition "$t" prototype --web-start "pnpm dev --port {port}" --web-port 5173) || {
    _fail "prototype definition should write"
    rm -rf "$t"
    return
  }
  python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["project"]["type"]=="prototype"' <<<"$prototype" \
    && pass_test || _fail "prototype definition output mismatch"
  rm -rf "$t"
}

test_paths_and_web_fail_closed() {
  start_test "project-definition: absolute/traversal paths and incomplete web config fail"
  local t rc1 rc2 rc3
  t=$(mktemp -d)
  write_spec "$t"
  write_definition "$t" product --root /tmp/app >/dev/null 2>&1
  rc1=$?
  write_definition "$t" product --entrypoint ../app >/dev/null 2>&1
  rc2=$?
  python3 "$PROJECT_DEFINITION" write "$t" \
    --source docs/modules/demo/spec.md --type product --root . --entrypoint app/ \
    --language typescript --runtime node --framework nextjs --package-manager pnpm \
    --build-command "pnpm run build" --web-start "pnpm dev" >/dev/null 2>&1
  rc3=$?
  rm -rf "$t"
  if [ "$rc1" != "0" ] && [ "$rc2" != "0" ] && [ "$rc3" != "0" ]; then
    pass_test
  else
    _fail "invalid project definition should fail: absolute=$rc1 traversal=$rc2 web=$rc3"
  fi
}

test_redefinition_requires_explicit_flag_and_revision() {
  start_test "project-definition: identity changes require explicit redefinition and revision bump"
  local t blocked updated
  t=$(mktemp -d)
  write_spec "$t"
  write_definition "$t" prototype --web-start "pnpm dev --port {port}" --web-port 3000 >/dev/null || {
    _fail "initial write failed"
    rm -rf "$t"
    return
  }
  write_definition "$t" product --web-start "pnpm dev --port {port}" --web-port 3000 >/dev/null 2>&1
  blocked=$?
  updated=$(write_definition "$t" product --web-start "pnpm dev --port {port}" --web-port 3000 --allow-redefinition) || {
    _fail "explicit redefinition failed"
    rm -rf "$t"
    return
  }
  rm -rf "$t"
  if [ "$blocked" != "0" ] && python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["definition"]["design_revision"]==2' <<<"$updated"; then
    pass_test
  else
    _fail "redefinition guard or revision bump mismatch"
  fi
}

test_commands_can_be_explicitly_empty() {
  start_test "project-definition: inapplicable commands may all be omitted"
  local t out
  t=$(mktemp -d)
  write_spec "$t"
  out=$(python3 "$PROJECT_DEFINITION" write "$t" \
    --source docs/modules/demo/spec.md --type prototype --root . --entrypoint public/ \
    --language html --runtime browser --framework static --package-manager none \
    --web-start "python3 -m http.server {port}" --web-port 8000) || {
      _fail "project definition should not require fake commands"
      rm -rf "$t"
      return
    }
  if python3 -c 'import json,sys; assert json.load(sys.stdin)["commands"] == {}' <<<"$out" \
     && grep -q '^commands: {}$' "$t/.pm-workflow/project.yml" \
     && python3 "$PROJECT_DEFINITION" validate "$t" >/dev/null; then
    pass_test
  else
    _fail "empty commands should round-trip as an explicit mapping"
  fi
  rm -rf "$t"
}

test_project_type_precedence_and_legacy() {
  start_test "project-type: project.yml wins; old config and system marker remain readable"
  local t modern old marker
  t=$(mktemp -d)
  write_spec "$t"
  mkdir -p "$t/.pm-workflow"
  printf 'project:\n  type: prototype\n' > "$t/.pm-workflow/config.yml"
  write_definition "$t" product >/dev/null || {
    _fail "modern definition write failed"
    rm -rf "$t"
    return
  }
  modern=$(python3 "$PROJECT_TYPE" "$t")
  rm -f "$t/.pm-workflow/project.yml"
  old=$(python3 "$PROJECT_TYPE" "$t")
  rm -f "$t/.pm-workflow/config.yml"
  printf '<!-- auto-detected: system -->\n' > "$t/CLAUDE.md"
  marker=$(python3 "$PROJECT_TYPE" "$t")
  rm -rf "$t"
  if [ "$modern" = "product" ] && [ "$old" = "prototype" ] && [ "$marker" = "product" ]; then
    pass_test
  else
    _fail "precedence mismatch: modern=$modern old=$old marker=$marker"
  fi
}

test_missing_definition_points_to_design() {
  start_test "project-type: new project without definition routes back to design"
  local t out rc
  t=$(mktemp -d)
  out=$(python3 "$PROJECT_TYPE" "$t" 2>&1)
  rc=$?
  rm -rf "$t"
  if [ "$rc" != "0" ] && echo "$out" | grep -q '/pmai-design' && echo "$out" | grep -q 'project.yml'; then
    pass_test
  else
    _fail "missing definition guidance mismatch: rc=$rc out=$out"
  fi
}

test_valid_prototype_and_product
test_paths_and_web_fail_closed
test_redefinition_requires_explicit_flag_and_revision
test_commands_can_be_explicitly_empty
test_project_type_precedence_and_legacy
test_missing_definition_points_to_design

report_results "project-definition"
