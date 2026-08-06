#!/usr/bin/env bash
# Host skill exposure must never replace an unowned shared-resource path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_HELPER="$REPO_ROOT/scripts/_lib/skill-links.sh"

test_installers_use_shared_ownership_helper() {
  start_test "skill links: install and upgrade share the ownership guard"
  if [ ! -f "$LINK_HELPER" ]; then
    _fail "missing shared ownership helper: $LINK_HELPER"
    return
  fi
  local file
  for file in "$REPO_ROOT/bin/pmai-install" "$REPO_ROOT/bin/pmai-upgrade" "$REPO_ROOT/bin/pmai-uninstall"; do
    if ! grep -q 'skill-links.sh' "$file"; then
      _fail "$(basename "$file") does not load skill-links.sh"
      return
    fi
  done
  pass_test
}

test_foreign_shared_directory_is_preserved() {
  start_test "skill links: foreign _shared directory is rejected and preserved"
  local t src dst out rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-links.XXXXXX")
  src="$t/pmai/skills/_shared"
  dst="$t/host/skills/_shared"
  mkdir -p "$src" "$dst"
  printf 'third party\n' > "$dst/third-party.txt"

  # shellcheck disable=SC1090
  source "$LINK_HELPER"
  out=$(pmai_install_shared_link "$src" "$dst" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "foreign _shared directory should block installation"
  elif [ ! -f "$dst/third-party.txt" ] || [ -L "$dst" ]; then
    _fail "foreign _shared directory was modified"
  elif ! echo "$out" | grep -q "不属于 PMAI"; then
    _fail "ownership conflict guidance missing: $out"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_managed_shared_link_can_be_refreshed() {
  start_test "skill links: PMAI-owned _shared symlink can be refreshed"
  local t src dst
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-links.XXXXXX")
  src="$t/pmai/skills/_shared"
  dst="$t/host/skills/_shared"
  mkdir -p "$src" "$(dirname "$dst")"
  ln -s "$src" "$dst"

  # shellcheck disable=SC1090
  source "$LINK_HELPER"
  if ! pmai_install_shared_link "$src" "$dst" >/dev/null 2>&1; then
    _fail "managed _shared link should be replaceable"
  elif [ "$(readlink "$dst")" != "$src" ]; then
    _fail "managed _shared link target drifted"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_foreign_shared_symlink_is_preserved() {
  start_test "skill links: foreign _shared symlink is rejected and preserved"
  local t src foreign dst out rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-links.XXXXXX")
  src="$t/pmai/skills/_shared"
  foreign="$t/third-party/shared"
  dst="$t/host/skills/_shared"
  mkdir -p "$src" "$foreign" "$(dirname "$dst")"
  ln -s "$foreign" "$dst"

  # shellcheck disable=SC1090
  source "$LINK_HELPER"
  out=$(pmai_install_shared_link "$src" "$dst" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "foreign _shared symlink should block installation"
  elif [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "$foreign" ]; then
    _fail "foreign _shared symlink was modified"
  elif ! echo "$out" | grep -q "不属于 PMAI"; then
    _fail "ownership conflict guidance missing: $out"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_installers_use_shared_ownership_helper
test_foreign_shared_directory_is_preserved
test_managed_shared_link_can_be_refreshed
test_foreign_shared_symlink_is_preserved

report_results "skill-link-ownership"
