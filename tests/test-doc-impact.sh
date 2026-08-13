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
  IMPLEMENTATION=$(git -C "$T" rev-parse HEAD)
  python3 - "$T/docs/modules/access/.work-meta.json" "$IMPLEMENTATION" <<'PY'
import json, sys
path, implementation = sys.argv[1:]
data = json.load(open(path))
data["build"]["implementation_commit"] = implementation
data["build"]["landed_commit"] = implementation
data["build"]["approved_source_hash"] = "a" * 64
json.dump(data, open(path, "w"), ensure_ascii=False, indent=2)
PY
}

teardown_fixture() { rm -rf "$T"; }

test_doc_impact_only_requires_affected_truth_sources() {
  start_test "doc-impact: only affected truth sources require manual coverage"
  setup_fixture
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  python3 "$DOC_IMPACT" init "$T/docs/modules/access" --repo-root "$T" --head HEAD --output "$MAP" >/dev/null
  if ! python3 - "$MAP" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))["items"]
destinations = {item["destination"] for item in items}
assert destinations == {
    "PRODUCT-STATE.md",
    "PRODUCT-RULES.md",
    "docs/modules/access/spec.md",
    "docs/modules/access/decisions.md",
}
assert not ({"PRODUCT.md", "DESIGN.md", "TODO.md", "docs/modules/INDEX.md", "docs/INDEX.md"} & destinations)
PY
  then
    _fail "unaffected fixed documents should not enter the map"; teardown_fixture; return
  fi
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
      python3 "$DOC_IMPACT" cover "$MAP" --item "$id" --status covered >/dev/null
    fi
  done
  if python3 "$DOC_IMPACT" validate "$MAP" >/dev/null; then pass_test; else _fail "covered map should pass"; fi
  teardown_fixture
}

test_doc_impact_without_delta_only_updates_product_state() {
  start_test "doc-impact: no accepted delta leaves one landed-state update"
  setup_fixture
  python3 - "$T/docs/modules/access/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["build"]["accepted_deltas"] = []
json.dump(data, open(path, "w"))
PY
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  python3 "$DOC_IMPACT" init "$T/docs/modules/access" --repo-root "$T" --head HEAD --output "$MAP" >/dev/null
  if python3 - "$MAP" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))["items"]
assert [(item["destination"], item["status"]) for item in items] == [("PRODUCT-STATE.md", "pending")]
PY
  then
    pass_test
  else
    _fail "no-delta document map should contain only PRODUCT-STATE"
  fi
  teardown_fixture
}

test_doc_impact_adds_structured_term_coverage() {
  start_test "doc-impact: landed structured terms require PRODUCT coverage"
  setup_fixture
  cat > "$T/docs/modules/access/spec.md" <<'MARKDOWN'
# Access

## 三、名词解释

| 术语 | 说明 |
| --- | --- |
| 授权批次 | 同一次授权操作产生的一组记录 |

## 五、用户与场景

### 5.1 用户角色

| 角色名 | 描述 |
| --- | --- |
| 授权审核员 | 审核高风险授权 |
MARKDOWN
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  python3 "$DOC_IMPACT" init "$T/docs/modules/access" --repo-root "$T" --head HEAD --output "$MAP" >/dev/null
  if python3 - "$MAP" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
items = data["items"]
product = next(item for item in items if item["destination"] == "PRODUCT.md")
assert product["kind"] == "term"
assert product["status"] == "pending"
assert data["term_reconciliation"]["new_terms"] == ["授权批次"]
assert data["term_reconciliation"]["new_roles"] == ["授权审核员"]
PY
  then
    pass_test
  else
    _fail "structured terms should create a pending PRODUCT.md impact"
  fi
  teardown_fixture
}

test_doc_impact_does_not_promote_discussion_terms_or_auto_cover_missing_terms() {
  start_test "doc-impact: draft terms stay out and unrelated PRODUCT edits do not cover missing terms"
  setup_fixture
  cat > "$T/docs/modules/access/discussion.md" <<'MARKDOWN'
# Discussion

## 名词解释

| 术语 | 说明 |
| --- | --- |
| 临时讨论名 | 尚未拍板的叫法 |
MARKDOWN
  cat > "$T/docs/modules/access/spec.md" <<'MARKDOWN'
# Access

## 名词解释

| 术语 | 说明 |
| --- | --- |
| 稳定授权单 | 一次已确认授权的正式记录 |
MARKDOWN
  printf '\n补充无关项目背景。\n' >> "$T/PRODUCT.md"
  git -C "$T" add docs/modules/access/discussion.md docs/modules/access/spec.md PRODUCT.md
  git -C "$T" commit -q -m "land docs"
  IMPLEMENTATION=$(git -C "$T" rev-parse HEAD)
  python3 - "$T/docs/modules/access/.work-meta.json" "$IMPLEMENTATION" <<'PY'
import json, sys
path, implementation = sys.argv[1:]
data = json.load(open(path))
data["build"]["implementation_commit"] = implementation
data["build"]["landed_commit"] = implementation
json.dump(data, open(path, "w"), ensure_ascii=False, indent=2)
PY

  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  python3 "$DOC_IMPACT" init "$T/docs/modules/access" --repo-root "$T" --head HEAD --output "$MAP" >/dev/null
  if python3 - "$MAP" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["term_reconciliation"]["new_terms"] == ["稳定授权单"]
product = next(item for item in data["items"] if item["destination"] == "PRODUCT.md")
assert product["status"] == "pending"
assert product["note"] == ""
PY
  then
    pass_test
  else
    _fail "draft term leaked or unrelated PRODUCT edit auto-covered a missing term"
  fi
  teardown_fixture
}

test_doc_impact_rebuilds_stale_schema_and_binding() {
  start_test "doc-impact: ensure-current rebuilds stale schema or source binding"
  setup_fixture
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  printf '{"schema_version":1,"items":[{"status":"covered"}]}\n' > "$MAP"
  python3 "$DOC_IMPACT" ensure-current "$T/docs/modules/access" \
    --repo-root "$T" --output "$MAP" >/dev/null || {
      _fail "old schema should rebuild"; teardown_fixture; return;
    }
  if ! python3 - "$MAP" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["schema_version"] == 2
assert data["binding"]["approved_source_hash"] == "a" * 64
assert data["binding"]["implementation_commit"] == data["binding"]["head"]
assert any(item["status"] == "pending" for item in data["items"])
PY
  then
    _fail "rebuilt map binding mismatch"; teardown_fixture; return
  fi
  python3 - "$T/docs/modules/access/.work-meta.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["build"]["approved_source_hash"] = "b" * 64
json.dump(data, open(path, "w"), ensure_ascii=False, indent=2)
PY
  if python3 "$DOC_IMPACT" validate "$MAP" >/tmp/doc-impact.$$ 2>&1; then
    _fail "stale source-bound map must not validate"
  elif grep -q "已过期" /tmp/doc-impact.$$; then
    pass_test
  else
    _fail "stale binding guidance mismatch"
    cat /tmp/doc-impact.$$ >&2
  fi
  rm -f /tmp/doc-impact.$$
  teardown_fixture
}

test_doc_impact_preserves_coverage_only_when_binding_is_current() {
  start_test "doc-impact: ensure-current preserves coverage only for identical binding"
  setup_fixture
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  python3 "$DOC_IMPACT" ensure-current "$T/docs/modules/access" \
    --repo-root "$T" --output "$MAP" >/dev/null
  ITEM=$(python3 - "$MAP" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["items"][0]["id"])
PY
  )
  python3 "$DOC_IMPACT" cover "$MAP" --item "$ITEM" --status covered >/dev/null
  BEFORE=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["items"][0]["checked_at"])' "$MAP")
  OUT=$(python3 "$DOC_IMPACT" ensure-current "$T/docs/modules/access" \
    --repo-root "$T" --output "$MAP")
  if python3 -c 'import json,sys; assert json.load(sys.stdin)["status"]=="current"' <<<"$OUT" \
    && [ "$BEFORE" = "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["items"][0]["checked_at"])' "$MAP")" ]; then
    pass_test
  else
    _fail "current map coverage should remain untouched"
  fi
  teardown_fixture
}

test_doc_impact_uses_legacy_candidate_snapshot_instead_of_old_baseline() {
  start_test "doc-impact: legacy candidate snapshot replaces stale baseline range"
  setup_fixture
  python3 - "$FRAMEWORK_ROOT" "$T" "$T/docs/modules/access/.work-meta.json" <<'PY'
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(sys.argv[1]) / "scripts"))
from _lib.candidate_binding import candidate_binding_digest, target_tree

root = Path(sys.argv[2])
path = Path(sys.argv[3])
data = json.loads(path.read_text(encoding="utf-8"))
build = data["build"]
source = build["implementation_commit"]
tree = target_tree(root, source, build["target"]["paths"])
binding = {
    "schema_version": 1,
    "source_kind": "legacy-recovery-checkpoint",
    "source_commit": source,
    "base_commit": source,
    "diff_mode": "approved-target-snapshot",
    "target_paths": tree["target_paths"],
    "target_tree_digest": tree["digest"],
    "approved_source_hash": build["approved_source_hash"],
    "bound_at": "2026-08-13T10:00:00+08:00",
}
binding["binding_digest"] = candidate_binding_digest(binding)
build["candidate_binding"] = binding
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
  MAP="$T/.pm-workflow/audits/access/doc-impact.json"
  if ! python3 "$DOC_IMPACT" ensure-current "$T/docs/modules/access" \
    --repo-root "$T" --output "$MAP" >/dev/null; then
    _fail "legacy candidate snapshot should build a current doc map"
  elif python3 - "$MAP" "$BASE" "$IMPLEMENTATION" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
binding = data["binding"]
assert binding["base"] == binding["head"] == sys.argv[3]
assert binding["base"] != sys.argv[2]
assert binding["candidate_diff_mode"] == "approved-target-snapshot"
assert binding["candidate_binding_digest"]
assert data["changed_files"] == ["prototype/access.tsx"]
PY
  then
    pass_test
  else
    _fail "legacy doc impact reused baseline or lost approved target snapshot"
  fi
  teardown_fixture
}

test_doc_impact_only_requires_affected_truth_sources
test_doc_impact_without_delta_only_updates_product_state
test_doc_impact_adds_structured_term_coverage
test_doc_impact_does_not_promote_discussion_terms_or_auto_cover_missing_terms
test_doc_impact_rebuilds_stale_schema_and_binding
test_doc_impact_preserves_coverage_only_when_binding_is_current
test_doc_impact_uses_legacy_candidate_snapshot_instead_of_old_baseline
report_results "doc-impact"
