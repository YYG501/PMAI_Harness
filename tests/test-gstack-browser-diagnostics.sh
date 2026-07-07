#!/usr/bin/env bash
# Static regression tests for gstack browser/design diagnostics.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/check-gstack-browser.sh"
DOCTOR="$REPO_ROOT/bin/pmai-doctor"
MOCKUP="$REPO_ROOT/skills/mockup/SKILL.md"

test_diagnostic_script_exists_and_documents_sandbox() {
  start_test "gstack diagnostics: script exists and explains sandbox"

  assert_file_exists "$SCRIPT" "gstack browser diagnostic script should exist" || return
  assert_file_contains "$SCRIPT" "EPERM" "script should detect EPERM" || return
  assert_file_contains "$SCRIPT" "Codex sandbox" "script should explain Codex sandbox restriction" || return
  assert_file_contains "$SCRIPT" "not necessarily a broken gstack browser" "script should avoid false broken-browser diagnosis" || return
  pass_test
}

test_diagnostic_script_avoids_browse_status() {
  start_test "gstack diagnostics: no browse status passive check"

  if grep -q '\$BROWSE_BIN.* status' "$SCRIPT" || grep -q ' browse status$' "$SCRIPT"; then
    _fail "diagnostic script must not call browse status as passive check"
    return
  fi
  assert_file_contains "$SCRIPT" "does not use \"browse status\"" "script should document why browse status is avoided" || return
  pass_test
}

test_diagnostic_script_has_optional_smoke() {
  start_test "gstack diagnostics: optional active smoke"

  assert_success "diagnostic --help should succeed" bash "$SCRIPT" --help || return
  assert_file_contains "$SCRIPT" "--browser-smoke" "script should expose browser-only active smoke flag" || return
  assert_file_contains "$SCRIPT" "--smoke" "script should expose explicit smoke flag" || return
  assert_file_contains "$SCRIPT" "--json-out" "script should write machine-readable browser smoke evidence" || return
  assert_file_contains "$SCRIPT" "active_browser_smoke" "json evidence should mark active browser smoke" || return
  assert_file_contains "$SCRIPT" 'status="skipped"' "passive json output should not claim active browser pass" || return
  assert_file_contains "$SCRIPT" "file://" "script should test local file navigation in smoke" || return
  assert_file_contains "$SCRIPT" "snapshot -i" "script should test interactive snapshot in smoke" || return
  assert_file_contains "$SCRIPT" "design compare" "script should smoke design compare board" || return
  pass_test
}

test_diagnostic_script_classifies_browser_launch_failures() {
  start_test "gstack diagnostics: smoke classifies browser launch failures"

  assert_file_contains "$SCRIPT" "Playwright Chromium is missing" "script should explain missing Playwright browser cache" || return
  assert_file_contains "$SCRIPT" "npx playwright install chromium" "script should print a concrete Playwright install hint" || return
  assert_file_contains "$SCRIPT" "macOS app bundle permission" "script should explain system Chrome app bundle EPERM" || return
  assert_file_contains "$SCRIPT" "passive diagnostics only" "doctor mode should not overclaim active browser readiness" || return
  assert_file_contains "$SCRIPT" "cannot write json result" "script should fail loudly if smoke evidence cannot be written" || return
  pass_test
}

test_doctor_and_mockup_reference_diagnostic() {
  start_test "gstack diagnostics: doctor and mockup wiring"

  assert_file_contains "$DOCTOR" "check-gstack-browser.sh" "doctor should call browser diagnostics" || return
  assert_file_contains "$DOCTOR" "--browser-smoke" "doctor should expose active browser smoke" || return
  assert_file_contains "$DOCTOR" "active smoke not run" "default doctor should avoid overclaiming active browser readiness" || return
  assert_file_contains "$DOCTOR" "gstack browser/design diagnostics" "doctor should expose diagnostic section" || return
  assert_file_contains "$MOCKUP" "check-gstack-browser.sh" "mockup should route through diagnostic script" || return
  assert_file_contains "$MOCKUP" '不要把 `browse status` 当无副作用检查' "mockup should warn about browse status side effect" || return
  pass_test
}

test_diagnostic_script_exists_and_documents_sandbox
test_diagnostic_script_avoids_browse_status
test_diagnostic_script_has_optional_smoke
test_diagnostic_script_classifies_browser_launch_failures
test_doctor_and_mockup_reference_diagnostic

report_results "gstack-browser-diagnostics"
