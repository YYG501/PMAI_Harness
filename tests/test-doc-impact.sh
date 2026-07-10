#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOC_IMPACT="$FRAMEWORK_ROOT/scripts/doc-impact.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-doc-impact.XXXXXX")
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  mkdir -p "$T/docs/modules/access" "$T/prototype" "$T/.pm-workflow/audits/access"
  echo '# state' > "$T/PRODUCT-STATE.md"
  echo '# rules' > "$T/PRODUCT-RULES.md"
  echo '# product' > "$T/PRODUCT.md"
  echo '# design' > "$T/DESIGN.md"
  echo '# todo' > "$T/TODO.md"
  echo '# index' > "$T/docs/modules/INDEX.md"
  echo '# spec' > "$T/docs/modules/access/spec.md"
  cat > "$T/docs/modules/access/.work-meta.json" <<'JSON'
{
  "id":"work-access","name":"access","status":"active",
  "build":{
    "contract_version":2,"baseline_sha":"BASE","implementation_commit":"IMPL",
    "landed_commit":"IMPL","target":{"kind":"prototype","paths":["prototype/"],"entrypoints":[]},
    "accepted_deltas":[{"kind":"cross-module-rule","summary":"权限范围改为授权时指定","affected_surfaces":["PRODUCT-RULES.md"]}]
  }
}
JSON
  git -C "$T" add -A && git -C "$T" commit -q -m base
  BASE=$(git -C "$T" rev-parse HEAD)
  python3 - "$T/docs/modules/access/.work-meta.json" "$BASE" <<'PY'
import json, sys
p=sys.argv[1]; d=json.load(open(p)); d["build"]["baseline_sha"]=sys.argv[2]
open(p,"w").write(json.dumps(d,ensure_ascii=False,indent=2)+"\n")
PY
  echo 'code' > "$T/prototype/access.tsx"
  git -C "$T" add -A && git -C "$T" commit -q -m implementation
}

teardown_fixture() { rm -rf "$T"; }

test_doc_impact_requires_every_surface() {
  start_test "doc-impact: default coverage + semantic item + fail until all accounted"
  setup_fixture
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  python3 "$DOC_IMPACT" init "$T/docs/modules/access" --repo-root "$T" --head HEAD --output "$MAP" >/dev/null
  EXTRA=$(python3 "$DOC_IMPACT" add "$MAP" --kind page --name "用户详情页授权记录" \
    --destination "docs/modules/access/spec.md")
  if python3 "$DOC_IMPACT" validate "$MAP" >/tmp/doc-impact.$$ 2>&1; then
    _fail "pending coverage should fail"; teardown_fixture; return
  fi
  IDS=()
  while IFS= read -r id; do
    [ -n "$id" ] && IDS[${#IDS[@]}]="$id"
  done < <(python3 - "$MAP" <<'PY'
import json,sys
for item in json.load(open(sys.argv[1]))["items"]: print(item["id"])
PY
  )
  for id in "${IDS[@]}"; do
    if [ "$id" = "$EXTRA" ]; then
      python3 "$DOC_IMPACT" cover "$MAP" --item "$id" --status covered --file "docs/modules/access/spec.md" >/dev/null
    else
      python3 "$DOC_IMPACT" cover "$MAP" --item "$id" --status no-change --note "已核对，当前文件无需改" >/dev/null
    fi
  done
  if python3 "$DOC_IMPACT" validate "$MAP" >/dev/null; then pass_test; else _fail "covered map should pass"; fi
  teardown_fixture
}

test_doc_impact_requires_every_surface
report_results "doc-impact"
