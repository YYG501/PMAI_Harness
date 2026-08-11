#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="$FRAMEWORK_ROOT/scripts/acceptance-profile.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"

write_definition() {
  local repo="$1" type="$2" root="$3" entrypoint="$4" web="$5"
  mkdir -p "$repo/docs/modules/demo"
  echo '# Demo' > "$repo/docs/modules/demo/spec.md"
  local args=(
    write "$repo" --source docs/modules/demo/spec.md --type "$type"
    --root "$root" --entrypoint "$entrypoint"
    --language typescript --runtime node --framework nextjs --package-manager pnpm
    --build-command "pnpm run build" --test-command "pnpm run test"
    --typecheck-command "pnpm run typecheck"
  )
  if [ "$web" = "yes" ]; then
    args+=(--web-start "pnpm dev --port {port}" --web-port 3000)
  fi
  python3 "$PROJECT_DEFINITION" "${args[@]}" >/dev/null
}

test_project_definition_profiles() {
  start_test "acceptance-profile: project.yml drives prototype/web-product/non-web-product checks"
  local t proto web_product backend
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-acceptance.XXXXXX")
  write_definition "$t" prototype prototype/ prototype/ yes
  proto=$(python3 "$PROFILE" --repo-root "$t" --project-definition "$t/.pm-workflow/project.yml" --path prototype/page.tsx)
  rm -f "$t/.pm-workflow/project.yml"
  write_definition "$t" product . app/ yes
  web_product=$(python3 "$PROFILE" --repo-root "$t" --project-definition "$t/.pm-workflow/project.yml" --path app/page.tsx)
  backend=$(python3 "$PROFILE" --repo-root "$t" --project-definition "$t/.pm-workflow/project.yml" --path server/api.ts)
  rm -rf "$t"
  if python3 -c 'import json,sys; d=json.load(sys.stdin); final=[x["name"] for x in d["final_checks"]]; iteration=[x["name"] for x in d["iteration_checks"]]; assert d["schema_version"]==3; assert final==["prototype-boundary","tests","typecheck","build","browser-acceptance","coverage"]; assert iteration==["typecheck","current-page"]; assert "required_checks" not in d; assert d["delivery_policy"]["implementation_mode"]=="interactive-simulation"; assert d["delivery_policy"]["required_check"]=="prototype-boundary"; assert len(d["delivery_policy_hash"])==64' <<<"$proto" \
    && python3 -c 'import json,sys; d=json.load(sys.stdin); n={x["name"] for x in d["final_checks"]}; i={x["name"] for x in d["iteration_checks"]}; assert {"scope-coverage","tests","typecheck","build","browser-acceptance"} <= n; assert not ({"browser-smoke","visual","behavior"} & n); assert i=={"typecheck","current-page"}' <<<"$web_product" \
    && python3 -c 'import json,sys; d=json.load(sys.stdin); n={x["name"] for x in d["final_checks"]}; i={x["name"] for x in d["iteration_checks"]}; assert "browser-acceptance" not in n; assert i=={"typecheck"}' <<<"$backend"; then
    pass_test
  else
    _fail "project.yml adaptive checks mismatch"
  fi
}

test_missing_project_definition_fails() {
  start_test "acceptance-profile: missing project.yml fails closed"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-acceptance.XXXXXX")
  if python3 "$PROFILE" --repo-root "$T" --project-definition .pm-workflow/project.yml >/tmp/acceptance.$$ 2>/tmp/acceptance.err.$$; then
    _fail "missing project.yml should block acceptance compilation"
  elif grep -q '/pmai-design' /tmp/acceptance.err.$$; then
    pass_test
  else
    _fail "missing project.yml guidance should route to design"
  fi
  rm -f /tmp/acceptance.$$ /tmp/acceptance.err.$$
  rm -rf "$T"
}

test_product_profile_uses_declared_commands_and_risk_adapters() {
  start_test "acceptance-profile: product uses project.yml commands + UI/migration/security checks"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-acceptance.XXXXXX")
  write_definition "$T" product . app/ yes
  out=$(python3 "$PROFILE" --repo-root "$T" --project-definition "$T/.pm-workflow/project.yml" --path app/page.tsx --data-migration --security-sensitive)
  python3 -c 'import json,sys; d=json.load(sys.stdin); n={x["name"]:x for x in d["final_checks"]}; assert {"scope-coverage","tests","typecheck","build","browser-acceptance","migration","security"} <= set(n); assert n["tests"]["command"]=="pnpm run test"' <<<"$out" \
    && pass_test || _fail "product checks mismatch"
  rm -rf "$T"
}

test_non_web_product_does_not_require_browser() {
  start_test "acceptance-profile: non-Web product does not require browser"
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-acceptance.XXXXXX")
  write_definition "$T" product . Sources/Service/ no
  out=$(python3 "$PROFILE" --repo-root "$T" --project-definition "$T/.pm-workflow/project.yml" --path Sources/Service/API.swift)
  python3 -c 'import json,sys; n={x["name"] for x in json.load(sys.stdin)["final_checks"]}; assert "browser-acceptance" not in n' <<<"$out" \
    && pass_test || _fail "non-Web product should not add browser checks"
  rm -rf "$T"
}

test_project_definition_profiles
test_missing_project_definition_fails
test_product_profile_uses_declared_commands_and_risk_adapters
test_non_web_product_does_not_require_browser
report_results "acceptance-profile"
