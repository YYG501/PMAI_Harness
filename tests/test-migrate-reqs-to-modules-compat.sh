#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MIGRATE="$REPO_ROOT/scripts/migrate-reqs-to-modules.py"

test_no_legacy_tree_is_noop() {
  start_test "T1: migrate-reqs-to-modules --dry-run no legacy tree exits 0"
  local tmp out rc
  tmp=$(mktemp -d)
  out=$(python3 "$MIGRATE" --dry-run "$tmp" 2>&1)
  rc=$?
  rm -rf "$tmp"
  if [ "$rc" != "0" ]; then
    _fail "expected exit 0, got $rc: $out"
    return
  fi
  if ! echo "$out" | grep -q "No legacy requirements/active|closed tree found"; then
    _fail "missing no-op guidance: $out"
    return
  fi
  pass_test
}

test_legacy_tree_inventories_and_refuses_apply() {
  start_test "T2: migrate-reqs-to-modules inventories legacy reqs and refuses --apply"
  local tmp out rc
  tmp=$(mktemp -d)
  mkdir -p "$tmp/requirements/active/req-001-demo"
  cat > "$tmp/requirements/active/req-001-demo/.req-meta.json" <<'JSON'
{"status":"active","stage":3,"module":"demo"}
JSON
  out=$(python3 "$MIGRATE" --apply "$tmp" 2>&1)
  rc=$?
  rm -rf "$tmp"
  if [ "$rc" = "0" ]; then
    _fail "--apply should refuse unsafe automatic migration"
    echo "$out" >&2
    return
  fi
  if ! echo "$out" | grep -q "requirements/active/req-001-demo"; then
    _fail "legacy inventory did not include req path: $out"
    return
  fi
  if ! echo "$out" | grep -q -- "--apply refused"; then
    _fail "missing explicit apply refusal: $out"
    return
  fi
  pass_test
}

test_no_legacy_tree_is_noop
test_legacy_tree_inventories_and_refuses_apply

report_results "migrate-reqs-to-modules-compat"
