#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTEXT_PACK="$FRAMEWORK_ROOT/scripts/context-pack.py"
PROJECT_DEFINITION="$FRAMEWORK_ROOT/scripts/project-definition.py"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-context-pack.XXXXXX")
  git -C "$T" init -q -b main
  git -C "$T" config user.email test@example.com
  git -C "$T" config user.name Test
  mkdir -p "$T/docs/modules/access" "$T/docs/decisions" "$T/prototype/src/pages"
  echo '# 产品' > "$T/PRODUCT.md"
  echo '# 现状' > "$T/PRODUCT-STATE.md"
  cat > "$T/PRODUCT-RULES.md" <<'EOF'
# 产品规则
## 规则清单
<!--
### <一句话标题>
- 规则：<产品在 X 情况下应 / 不应 Y>
-->
## R1 权限不随部门自动继承
加入部门不会自动获得管理权限。
EOF
  echo '# 设计' > "$T/DESIGN.md"
  echo '# TODO' > "$T/TODO.md"
  cat > "$T/docs/modules/access/decisions.md" <<'EOF'
# 决策
## D1 角色只定义能力
角色只回答能做什么，范围在授权时指定。
## D2 是否保留产品详情里的角色入口？
这是尚未回答的问题？
## ~~D3 部门自动带角色~~
已被 D1 取代。
## 2. 共同理由
角色与范围分开维护。
## 3. 否过的方案
- 部门自动带角色。
## 4. 待复核决策
本轮没有待复核决策。
## 5. 变更记录
- 2026-07-14：确认角色边界。
EOF
  cat > "$T/docs/modules/access/discussion.md" <<'EOF'
# 讨论
- 待确认：用户详情页是否展示授权记录？
EOF
  echo '# 当前规格' > "$T/docs/modules/access/spec.md"
  python3 "$PROJECT_DEFINITION" write "$T" \
    --source docs/modules/access/spec.md --type prototype \
    --root prototype/ --entrypoint prototype/ \
    --language typescript --runtime node --framework nextjs --package-manager pnpm \
    --build-command "pnpm run build" >/dev/null
  cat > "$T/docs/modules/access/.work-meta.json" <<'EOF'
{"id":"work-access","name":"access","stage":1,"status":"active","lifecycle_state":"designing"}
EOF
  echo 'export default function RolePage(){}' > "$T/prototype/src/pages/access-role.tsx"
  git -C "$T" add -A
  git -C "$T" commit -q -m init
}

teardown_fixture() { rm -rf "$T"; }

test_context_pack_compiles_authority_and_rejects_questions() {
  start_test "context-pack: active/superseded decisions + question rejection + unresolved questions"
  setup_fixture
  OUT="$T/context.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module access \
    --goal "权限角色" --output "$OUT" >/dev/null || {
      _fail "context pack should compile"; teardown_fixture; return;
    }
  python3 - "$OUT" <<'PY' || {
import json, sys
data = json.load(open(sys.argv[1]))
assert data["module"] == "docs/modules/access"
assert data["target"]["kind"] == "prototype"
assert any(item["title"].startswith("D1") for item in data["decisions"]["active"])
assert any(item["title"].startswith("D2") for item in data["decisions"]["question_like_rejected"])
assert any(item["status"] == "superseded" for item in data["decisions"]["superseded"])
assert data["unresolved_questions"]
assert "prototype/src/pages/access-role.tsx" in data["relevant_implementation_paths"]
assert data["source_hash"]
PY
    _fail "compiled context fields mismatch"; teardown_fixture; return;
  }
  pass_test
  teardown_fixture
}

test_context_pack_hash_changes_with_authority_source() {
  start_test "context-pack: authority edit changes source_hash"
  setup_fixture
  H1=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module access | python3 -c 'import json,sys; print(json.load(sys.stdin)["source_hash"])')
  echo '补一条当前规则' >> "$T/PRODUCT-RULES.md"
  H2=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module access | python3 -c 'import json,sys; print(json.load(sys.stdin)["source_hash"])')
  if [ "$H1" != "$H2" ]; then pass_test; else _fail "source_hash should change"; fi
  teardown_fixture
}

test_context_pack_ignores_resolved_headings_and_non_decision_sections() {
  start_test "context-pack: resolved heading and decision metadata are not product decisions"
  setup_fixture
  cat > "$T/docs/modules/access/discussion.md" <<'EOF'
# 讨论
## 待确认问题
本轮全部已确认。
EOF
  OUT="$T/context-filtered.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module access --output "$OUT" >/dev/null || {
    _fail "context pack should compile filtered decisions"; teardown_fixture; return;
  }
  python3 - "$OUT" <<'PY' || {
import json, sys
data = json.load(open(sys.argv[1]))
active = [item["title"] for item in data["decisions"]["active"]]
assert any(title.startswith("D1") for title in active)
assert any(title.startswith("R1") for title in active)
assert not any("共同理由" in title for title in active)
assert not any("否过" in title for title in active)
assert not any("待复核" in title for title in active)
assert not any("变更记录" in title for title in active)
assert not any("一句话标题" in title for title in active)
assert data["unresolved_questions"] == []
PY
    _fail "resolved headings or metadata leaked into context decisions"; teardown_fixture; return;
  }
  pass_test
  teardown_fixture
}

test_context_pack_recognizes_current_round_has_no_open_questions() {
  start_test "context-pack: 本轮工作无未决问题不进入 unresolved_questions"
  setup_fixture
  cat > "$T/docs/modules/access/discussion.md" <<'EOF'
# 讨论

## 未决问题

本轮工作无未决问题。
EOF
  local out
  out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module access 2>&1) || {
    _fail "context pack should compile explicit no-open statement"
    teardown_fixture
    return
  }
  if python3 -c 'import json,sys; assert json.load(sys.stdin)["unresolved_questions"] == []' <<<"$out"; then
    pass_test
  else
    _fail "explicit no-open statement was reported as unresolved: $out"
  fi
  teardown_fixture
}

test_context_pack_lifecycle_state_does_not_drift_approved_source() {
  start_test "context-pack: lifecycle metadata hash is tracked but excluded from approved source hash"
  setup_fixture
  OUT1="$T/context-1.json"
  OUT2="$T/context-2.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module access --output "$OUT1" >/dev/null
  cat > "$T/docs/modules/access/.work-meta.json" <<'EOF'
{"id":"work-access","name":"access","stage":2,"status":"active","lifecycle_state":"iterating"}
EOF
  python3 "$CONTEXT_PACK" --repo-root "$T" --module access --output "$OUT2" >/dev/null
  python3 - "$OUT1" "$OUT2" <<'PY' || {
import json, sys
before = json.load(open(sys.argv[1]))
after = json.load(open(sys.argv[2]))
path = "docs/modules/access/.work-meta.json"
assert before["source_hash"] == after["source_hash"]
assert before["input_hashes"][path] != after["input_hashes"][path]
assert path not in before["source_hash_scope"]
PY
    _fail "lifecycle state should not change approved source hash"; teardown_fixture; return
  }
  pass_test
  teardown_fixture
}

test_context_pack_includes_registered_input_evidence() {
  start_test "context-pack: registered docs/inputs evidence is hashed"
  setup_fixture
  mkdir -p "$T/docs/inputs/product-sources"
  echo 'source version one' > "$T/docs/inputs/product-sources/access-source.md"
  cat > "$T/docs/modules/access/.work-meta.json" <<'EOF'
{"id":"work-access","name":"access","stage":1,"status":"active","lifecycle_state":"designing","attachments_seen":[{"name":"docs/inputs/product-sources/access-source.md"}]}
EOF
  OUT1="$T/context-evidence-1.json"
  OUT2="$T/context-evidence-2.json"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module access --output "$OUT1" >/dev/null
  echo 'source version two' > "$T/docs/inputs/product-sources/access-source.md"
  python3 "$CONTEXT_PACK" --repo-root "$T" --module access --output "$OUT2" >/dev/null
  python3 - "$OUT1" "$OUT2" <<'PY' || {
import json, sys
before = json.load(open(sys.argv[1]))
after = json.load(open(sys.argv[2]))
path = "docs/inputs/product-sources/access-source.md"
assert any(item["path"] == path and item["role"] == "input_evidence" for item in before["sources"])
assert path in before["source_hash_scope"]
assert before["source_hash"] != after["source_hash"]
PY
    _fail "registered input evidence should enter the approved source hash"; teardown_fixture; return
  }
  pass_test
  teardown_fixture
}

test_context_pack_compiles_authority_and_rejects_questions
test_context_pack_hash_changes_with_authority_source
test_context_pack_ignores_resolved_headings_and_non_decision_sections
test_context_pack_recognizes_current_round_has_no_open_questions
test_context_pack_lifecycle_state_does_not_drift_approved_source
test_context_pack_includes_registered_input_evidence
report_results "context-pack"
