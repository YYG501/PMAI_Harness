#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="$FRAMEWORK_ROOT/scripts/acceptance-profile.py"

test_prototype_profile() {
  start_test "acceptance-profile: prototype uses browser/coverage/visual/behavior"
  out=$(python3 "$PROFILE" --repo-root "$FRAMEWORK_ROOT" --target prototype)
  python3 -c 'import json,sys; n=[x["name"] for x in json.load(sys.stdin)["required_checks"]]; assert n==["browser-smoke","coverage","visual","behavior"]' <<<"$out" \
    && pass_test || _fail "prototype checks mismatch"
}

test_product_profile_detects_repo_commands_and_risk_adapters() {
  start_test "acceptance-profile: product detects scripts + UI/migration/security checks"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-acceptance.XXXXXX")
  cat > "$T/package.json" <<'JSON'
{"scripts":{"test":"vitest run","typecheck":"tsc --noEmit","build":"vite build"}}
JSON
  touch "$T/pnpm-lock.yaml"
  out=$(python3 "$PROFILE" --repo-root "$T" --target product --path src/app/page.tsx --ui yes --data-migration --security-sensitive)
  python3 -c 'import json,sys; d=json.load(sys.stdin); n={x["name"]:x for x in d["required_checks"]}; assert {"scope-coverage","tests","typecheck","build","browser-smoke","visual","behavior","migration","security"} <= set(n); assert n["tests"]["command"]=="pnpm run test"' <<<"$out" \
    && pass_test || _fail "product checks mismatch"
  rm -rf "$T"
}

test_product_profile_does_not_add_ui_checks_for_backend_target() {
  start_test "acceptance-profile: explicit backend path does not inherit unrelated repo UI checks"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-acceptance.XXXXXX")
  mkdir -p "$T/src/app" "$T/server/api"
  cat > "$T/package.json" <<'JSON'
{"scripts":{"test":"vitest run"}}
JSON
  out=$(python3 "$PROFILE" --repo-root "$T" --target product --path server/api/roles.ts)
  python3 -c 'import json,sys; n={x["name"] for x in json.load(sys.stdin)["required_checks"]}; assert "tests" in n; assert not ({"browser-smoke","visual","behavior"} & n)' <<<"$out" \
    && pass_test || _fail "backend target should not add UI checks"
  rm -rf "$T"
}

test_product_profile_does_not_treat_sources_as_browser_ui() {
  start_test "acceptance-profile: Sources backend target does not imply browser UI"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-acceptance.XXXXXX")
  mkdir -p "$T/Sources/Service"
  out=$(python3 "$PROFILE" --repo-root "$T" --target product --path Sources/Service/API.swift)
  python3 -c 'import json,sys; n={x["name"] for x in json.load(sys.stdin)["required_checks"]}; assert not ({"browser-smoke","visual","behavior"} & n)' <<<"$out" \
    && pass_test || _fail "Sources backend should not add browser UI checks"
  rm -rf "$T"
}

test_prototype_profile
test_product_profile_detects_repo_commands_and_risk_adapters
test_product_profile_does_not_add_ui_checks_for_backend_target
test_product_profile_does_not_treat_sources_as_browser_ui
report_results "acceptance-profile"
