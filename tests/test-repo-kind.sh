#!/usr/bin/env bash
# Unique generator / consumer / uninitialized repository identity contract.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/repo-kind.py"
PREAMBLE="$REPO_ROOT/scripts/skill-preamble.sh"

assert_kind() {
  local root="$1" expected="$2" actual
  actual=$(python3 "$RESOLVER" --repo-root "$root" 2>/dev/null) || return 1
  [ "$actual" = "$expected" ]
}

test_generator_identity_is_strict() {
  start_test "repo-kind: generator requires the full framework marker set"
  local tmp
  tmp=$(mktemp -d)
  mkdir -p "$tmp/scripts"
  touch "$tmp/scripts/init-project.sh"
  if ! assert_kind "$REPO_ROOT" generator; then
    _fail "framework checkout should be generator"
  elif ! assert_kind "$tmp" uninitialized; then
    _fail "scripts/init-project.sh alone must not impersonate a generator"
  else
    pass_test
  fi
  rm -rf "$tmp"
}

test_consumer_and_generic_docs_are_distinct() {
  start_test "repo-kind: PMAI marker combinations identify consumers without claiming ordinary product repos"
  local tmp generic consumer
  tmp=$(mktemp -d)
  generic="$tmp/generic"
  consumer="$tmp/consumer"
  mkdir -p "$generic/docs" "$generic/.codex" "$consumer/docs"
  printf '# ordinary docs\n' > "$generic/docs/README.md"
  printf '# Ordinary product\n' > "$generic/PRODUCT.md"
  printf '{"hooks": []}\n' > "$generic/.codex/hooks.json"
  printf '# Product\n' > "$consumer/PRODUCT.md"
  printf '# Product state\n' > "$consumer/PRODUCT-STATE.md"
  if ! assert_kind "$generic" uninitialized; then
    _fail "generic docs, PRODUCT.md, and non-PMAI Codex hooks should stay uninitialized"
  elif ! assert_kind "$consumer" consumer; then
    _fail "the legacy PMAI product spine should identify a consumer"
  else
    pass_test
  fi
  rm -rf "$tmp"
}

test_marker_symlink_cannot_escape_root() {
  start_test "repo-kind: marker symlinks outside the checkout do not grant identity"
  local tmp repo outside
  tmp=$(mktemp -d)
  repo="$tmp/repo"
  outside="$tmp/outside-product.md"
  mkdir -p "$repo"
  printf '# Product\n' > "$outside"
  ln -s "$outside" "$repo/PRODUCT.md"
  if assert_kind "$repo" uninitialized; then
    pass_test
  else
    _fail "out-of-root marker symlink must be ignored"
  fi
  rm -rf "$tmp"
}

test_attached_generator_worktree_is_generator() {
  start_test "repo-kind: attached framework worktree keeps generator identity"
  local tmp repo worktree
  tmp=$(mktemp -d)
  repo="$tmp/repo"
  worktree="$tmp/worktree"
  mkdir -p "$repo/skills/init-project"
  printf '# Runtime\n' > "$repo/RUNTIME.md"
  printf '# Claude\n' > "$repo/CLAUDE.md"
  printf '# Init\n' > "$repo/skills/init-project/SKILL.md"
  git -C "$repo" init -q -b main
  git -C "$repo" add -A
  git -C "$repo" -c user.name=PMAI-Test -c user.email=pmai-test@example.invalid commit -q -m init
  git -C "$repo" worktree add -q -b fixture-worktree "$worktree"
  if assert_kind "$worktree" generator; then
    pass_test
  else
    _fail "attached worktree should be classified from its own marker files"
  fi
  git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}

test_preamble_exports_kind_and_compatibility_projection() {
  start_test "repo-kind: preamble exports canonical kind and legacy initialized projection"
  local tmp out
  tmp=$(mktemp -d)
  git -C "$tmp" init -q -b main
  out=$(cd "$tmp" && PMAI_HOME="$REPO_ROOT" bash -lc 'source "$PMAI_HOME/scripts/skill-preamble.sh"' 2>&1)
  if ! echo "$out" | grep -q 'PMAI_REPO_KIND: uninitialized'; then
    _fail "preamble should export uninitialized kind: $out"
  elif ! echo "$out" | grep -q 'PMAI_PROJECT_INITIALIZED: 0'; then
    _fail "legacy initialized projection should remain 0: $out"
  else
    pass_test
  fi
  rm -rf "$tmp"
}

test_invalid_root_fails_closed() {
  start_test "repo-kind: unreadable or missing roots fail closed"
  local tmp rc
  tmp=$(mktemp -d)
  python3 "$RESOLVER" --repo-root "$tmp/missing" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "2" ]; then
    pass_test
  else
    _fail "missing root should return rc=2, got $rc"
  fi
  rm -rf "$tmp"
}

test_generator_identity_is_strict
test_consumer_and_generic_docs_are_distinct
test_marker_symlink_cannot_escape_root
test_attached_generator_worktree_is_generator
test_preamble_exports_kind_and_compatibility_projection
test_invalid_root_fails_closed

report_results "repo-kind"
