#!/usr/bin/env bash
# Project-level prototype/product definition regressions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_TYPE="$REPO_ROOT/scripts/project-type.py"
INIT_PROJECT="$REPO_ROOT/scripts/init-project.sh"
CONFIG_TMPL="$REPO_ROOT/templates/pm-workflow.config.yml.tmpl"

test_reads_explicit_project_type() {
  start_test "project-type: explicit config is the source of truth"
  local t out
  t=$(mktemp -d)
  mkdir -p "$t/.pm-workflow"
  printf 'project:\n  type: product\n' > "$t/.pm-workflow/config.yml"
  out=$(python3 "$PROJECT_TYPE" "$t" 2>&1)
  if [ "$?" = "0" ] && [ "$out" = "product" ]; then
    pass_test
  else
    _fail "expected product, got: $out"
  fi
  rm -rf "$t"
}

test_legacy_markers_map_without_guessing() {
  start_test "project-type: legacy prototype/system markers map deterministically"
  local t p s
  t=$(mktemp -d)
  printf '<!-- auto-detected: prototype -->\n' > "$t/CLAUDE.md"
  p=$(python3 "$PROJECT_TYPE" "$t" 2>&1)
  printf '<!-- auto-detected: system -->\n' > "$t/CLAUDE.md"
  s=$(python3 "$PROJECT_TYPE" "$t" 2>&1)
  if [ "$p" = "prototype" ] && [ "$s" = "product" ]; then
    pass_test
  else
    _fail "legacy mapping mismatch: prototype=$p system=$s"
  fi
  rm -rf "$t"
}

test_unknown_legacy_requires_definition_file() {
  start_test "project-type: custom/unknown legacy projects must define config"
  local t out rc
  t=$(mktemp -d)
  printf '<!-- auto-detected: custom -->\n' > "$t/CLAUDE.md"
  out=$(python3 "$PROJECT_TYPE" "$t" 2>&1)
  rc=$?
  if [ "$rc" != "0" ] && echo "$out" | grep -q '.pm-workflow/config.yml'; then
    pass_test
  else
    _fail "custom marker should fail with config instruction: rc=$rc out=$out"
  fi
  rm -rf "$t"
}

test_invalid_explicit_type_never_falls_back() {
  start_test "project-type: invalid explicit type fails even with a legacy marker"
  local t out rc
  t=$(mktemp -d)
  mkdir -p "$t/.pm-workflow"
  printf 'project:\n  type: system\n' > "$t/.pm-workflow/config.yml"
  printf '<!-- auto-detected: prototype -->\n' > "$t/CLAUDE.md"
  out=$(python3 "$PROJECT_TYPE" "$t" 2>&1)
  rc=$?
  if [ "$rc" != "0" ] && echo "$out" | grep -q 'prototype 或 product'; then
    pass_test
  else
    _fail "invalid explicit type should fail closed: rc=$rc out=$out"
  fi
  rm -rf "$t"
}

test_init_contract_writes_type_and_maps_product_structure() {
  start_test "init-project: writes project.type and maps product to system structure internally"
  assert_file_contains "$CONFIG_TMPL" 'type: {{PROJECT_TYPE}}' "config template should persist project type" || return
  assert_file_contains "$INIT_PROJECT" 'PROJECT_TYPE="$4"' "init should require project type" || return
  assert_file_contains "$INIT_PROJECT" 'STRUCTURE_INTENT="system"' "product should map to system structure template" || return
  assert_file_contains "$INIT_PROJECT" 'text.replace("{{PROJECT_TYPE}}"' "init should replace project type placeholder" || return
  pass_test
}

test_reads_explicit_project_type
test_legacy_markers_map_without_guessing
test_unknown_legacy_requires_definition_file
test_invalid_explicit_type_never_falls_back
test_init_contract_writes_type_and_maps_product_structure

report_results "project-type"
