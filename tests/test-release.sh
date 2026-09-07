#!/usr/bin/env bash
# Release workflow and rolling-main update checks.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASE="$REPO_ROOT/scripts/release.py"

make_fixture() {
  local dir="$1"
  mkdir -p "$dir/bin" "$dir/scripts"
  cp "$RELEASE" "$dir/scripts/release.py"
  cp "$REPO_ROOT/scripts/release-gate-preflight.py" "$dir/scripts/release-gate-preflight.py"
  printf '#!/usr/bin/env bash\n' > "$dir/bin/pmai"
  chmod +x "$dir/bin/pmai"
  printf '0.2.1\n' > "$dir/VERSION"
  printf '# CHANGELOG\n\n## 未发布\n\n- 新的产品能力\n- 对应的回归证据\n\n## v0.2.1 — 2026-05-27\n\n- 旧版本内容\n' > "$dir/CHANGELOG.md"
  git -C "$dir" init -q
  git -C "$dir" checkout -q -b main
  git -C "$dir" config user.name "PMAI Test"
  git -C "$dir" config user.email "pmai-test@example.invalid"
  git -C "$dir" add .
  git -C "$dir" commit -q -m initial
}

test_prepare_archives_unreleased_and_commits() {
  start_test "release: prepare bumps VERSION, archives CHANGELOG, and commits candidate"
  local tmp out rc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/pmai-release.XXXXXX")
  make_fixture "$tmp"
  out=$(cd "$tmp" && python3 scripts/release.py prepare --bump minor --date 2026-09-07 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$(cat "$tmp/VERSION")" != "0.3.0" ]; then
    _fail "prepare should create v0.3.0: rc=$rc output=$out"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q '^## v0.3.0 — 2026-09-07$' "$tmp/CHANGELOG.md" \
    || ! grep -q '新的产品能力' "$tmp/CHANGELOG.md" \
    || ! grep -q '（暂无未发布变更）' "$tmp/CHANGELOG.md"; then
    _fail "prepare should move unreleased entries into a versioned section"
    rm -rf "$tmp"
    return
  fi
  if ! git -C "$tmp" log -1 --format=%s | grep -q '^release: v0.3.0$'; then
    _fail "prepare should create a release commit"
    rm -rf "$tmp"
    return
  fi
  out=$(cd "$tmp" && python3 scripts/release.py check 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q 'release v0.3.0 结构预检通过'; then
    _fail "prepared release should pass structural check: rc=$rc output=$out"
    rm -rf "$tmp"
    return
  fi
  out=$(cd "$tmp" && python3 scripts/release.py notes --version v0.3.0 2>&1)
  if ! echo "$out" | grep -q '新的产品能力'; then
    _fail "notes should print the versioned changelog body"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_prepare_rejects_empty_unreleased() {
  start_test "release: empty unreleased section cannot create a release"
  local tmp out rc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/pmai-release.XXXXXX")
  make_fixture "$tmp"
  sed -i.bak 's/- 新的产品能力/（暂无未发布变更）/; /- 对应的回归证据/d' "$tmp/CHANGELOG.md"
  rm -f "$tmp/CHANGELOG.md.bak"
  git -C "$tmp" add CHANGELOG.md
  git -C "$tmp" commit -q -m "empty unreleased fixture"
  out=$(cd "$tmp" && python3 scripts/release.py prepare --bump patch 2>&1)
  rc=$?
  if [ "$rc" -ne 2 ] || ! echo "$out" | grep -q '没有可归档的变更'; then
    _fail "empty unreleased should fail closed: rc=$rc output=$out"
    rm -rf "$tmp"
    return
  fi
  rm -rf "$tmp"
  pass_test
}

test_update_check_uses_main_commit() {
  start_test "update-check: rolling main compares origin/main commits"
  local tmp remote state out rc old_head
  remote=$(mktemp -d "${TMPDIR:-/tmp}/pmai-release-remote.XXXXXX")
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/pmai-release-home.XXXXXX")
  state=$(mktemp -d "${TMPDIR:-/tmp}/pmai-release-state.XXXXXX")
  git init --bare -q "$remote"
  git init -q "$tmp"
  git -C "$tmp" checkout -q -b main
  git -C "$tmp" config user.name "PMAI Test"
  git -C "$tmp" config user.email "pmai-test@example.invalid"
  printf '0.2.1\n' > "$tmp/VERSION"
  git -C "$tmp" add VERSION
  git -C "$tmp" commit -q -m initial
  git -C "$tmp" remote add origin "$remote"
  git -C "$tmp" push -q -u origin main
  out=$(PMAI_HOME="$tmp" PMAI_STATE="$state" bash "$REPO_ROOT/bin/pmai-update-check" --force 2>&1)
  if [ -n "$out" ]; then
    _fail "up-to-date main should be silent: $out"
    rm -rf "$tmp" "$remote" "$state"
    return
  fi
  old_head=$(git -C "$tmp" rev-parse HEAD)
  printf 'new\n' >> "$tmp/VERSION"
  git -C "$tmp" add VERSION
  git -C "$tmp" commit -q -m newer
  git -C "$tmp" push -q origin main
  git -C "$tmp" reset --hard -q "$old_head"
  out=$(PMAI_HOME="$tmp" PMAI_STATE="$state" bash "$REPO_ROOT/bin/pmai-update-check" --force 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ] || ! echo "$out" | grep -q 'UPGRADE_AVAILABLE main@'; then
    _fail "main update should report commit channel: rc=$rc output=$out"
    rm -rf "$tmp" "$remote" "$state"
    return
  fi
  rm -rf "$tmp" "$remote" "$state"
  pass_test
}

test_release_cli_and_workflow_contract() {
  start_test "release: CLI dispatcher and GitHub release workflow are wired"
  local help
  help=$(bash "$REPO_ROOT/bin/pmai" --help)
  if ! echo "$help" | grep -q 'release'; then
    _fail "pmai help should expose generator release"
    return
  fi
  if ! grep -q 'permissions:' "$REPO_ROOT/.github/workflows/harness-release-gate.yml" \
    || ! grep -q 'contents: write' "$REPO_ROOT/.github/workflows/harness-release-gate.yml" \
    || ! grep -q 'gh release create' "$REPO_ROOT/.github/workflows/harness-release-gate.yml" \
    || ! grep -q 'scripts/release.py notes' "$REPO_ROOT/.github/workflows/harness-release-gate.yml"; then
    _fail "tag workflow should publish a GitHub Release after the gate"
    return
  fi
  pass_test
}

test_prepare_archives_unreleased_and_commits
test_prepare_rejects_empty_unreleased
test_update_check_uses_main_commit
test_release_cli_and_workflow_contract

report_results "release"
