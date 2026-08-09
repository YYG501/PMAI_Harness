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
## 历史讨论
- 待确认：历史版本是否展示授权记录？
## 未决问题
### Q1: 用户详情页是否展示授权记录？
**PM 回答：**
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
assert [(item["line"], item["text"]) for item in data["unresolved_questions"]] == [
    (5, "### Q1: 用户详情页是否展示授权记录？")
]
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

test_context_pack_rejects_quoted_or_qualified_no_open_claims() {
  start_test "context-pack: 否定、转述和附带未决项不冒充无未决声明"
  setup_fixture
  cat > "$T/docs/modules/access/discussion.md" <<'EOF'
# 讨论

## 未决问题

- 并非本轮工作无未决问题。
- 会议纪要写着“本轮工作无未决问题”。
- 本轮工作无未决问题，但退款规则仍待确认。
EOF
  local out
  out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module access 2>&1) || {
    _fail "context pack should compile qualified statements"
    teardown_fixture
    return
  }
  if python3 -c '
import json, sys
data = json.load(sys.stdin)
actual = [(item["line"], item["text"]) for item in data["unresolved_questions"]]
assert actual == [
    (5, "- 并非本轮工作无未决问题。"),
    (6, "- 会议纪要写着“本轮工作无未决问题”。"),
    (7, "- 本轮工作无未决问题，但退款规则仍待确认。"),
], actual
' <<<"$out"; then
    pass_test
  else
    _fail "qualified statements were incorrectly suppressed: $out"
  fi
  teardown_fixture
}

test_context_pack_only_reports_unanswered_current_questions() {
  start_test "context-pack: 只报告当前 section 内未回答的结构化问题"
  setup_fixture
  cat > "$T/docs/modules/access/discussion.md" <<'EOF'
# 讨论

## 未决问题

### Q0: 历史遗留问题

**PM 回答：**

## 历史讨论

- 待确认：这段历史内容不应回流。

## 待确认问题

### Q1: 已回答问题

题干里仍可能写待确认和问号？

**PM 回答：** 采用 A 方案。

### Q2: 缺回答标记

仅有背景说明。

### Q3: 空回答

**PM 回答：**
EOF
  local out
  out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module access 2>&1) || {
    _fail "context pack should compile structured open questions"
    teardown_fixture
    return
  }
  if python3 -c '
import json, sys
data = json.load(sys.stdin)
actual = [(item["line"], item["text"]) for item in data["unresolved_questions"]]
assert actual == [
    (21, "### Q2: 缺回答标记"),
    (25, "### Q3: 空回答"),
], actual
' <<<"$out"; then
    pass_test
  else
    _fail "historical or answered questions leaked into unresolved list: $out"
  fi
  teardown_fixture
}

test_context_pack_reports_invalid_open_question_section() {
  start_test "context-pack: 空壳开放问题 section 保持 unresolved"
  setup_fixture
  cat > "$T/docs/modules/access/discussion.md" <<'EOF'
# 讨论

## 未决问题

这里稍后整理。
EOF
  local out
  out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module access 2>&1) || {
    _fail "context pack should compile invalid open-question evidence"
    teardown_fixture
    return
  }
  if python3 -c '
import json, sys
items = json.load(sys.stdin)["unresolved_questions"]
assert len(items) == 1, items
assert items[0]["line"] == 3, items
assert "缺少可验证的问题" in items[0]["text"], items
' <<<"$out"; then
    pass_test
  else
    _fail "invalid section disappeared from unresolved questions: $out"
  fi
  teardown_fixture
}

test_context_pack_uses_shared_decision_status_semantics() {
  start_test "context-pack: 与术语检测共用决定状态和分句主语语义"
  setup_fixture
  cat > "$T/docs/modules/access/decisions.md" <<'EOF'
# 决策

## D1 本决定作废但旧版本有效
本决定已作废，但旧版本仍有效。

## D2 本决定有效但旧版本作废
本决定仍有效，但旧版本已作废。

## D3 新定名 supersedes D2
新决定保留。

## D4 当前定名已取代旧决定
新决定保留。

## D5 旧决定已作废
旧决定停用。

## D6 当前决定已被取代
本决定已由 D3 取代。

## D7 已废弃入口的迁移策略
迁移期保留旧链接跳转。

## D8 已作废订单的审计保留规则
作废订单继续保留审计记录。

## ~~D9 Current decision~~
Status: this decision is still valid

## D10 当前决定是否被取代
尚未确认状态。

## D11 被新规则取代时的迁移流程
迁移期保留旧链接跳转。

## D12 当前决定
状态：被 D3 取代时保留审计记录。

## D13 Migration when decision is superseded
Keep the audit record during migration.

## D14 不再有效入口的迁移策略
迁移期保留旧链接跳转。

## D15 登录入口继续有效
为什么还要保留旧入口？
结论：继续保留登录入口。

## D16 是否统一采用邮箱登录？
结论：统一采用邮箱登录。

## D17 当前决定是否继续有效？
状态：仍有效

## D18 当前决定是否继续有效？
尚未确认。

## D19 当前决定是否继续有效？
状态：已作废

## D20 登录入口方案
是否保留旧入口？

## D21 当前决定
状态：尚未正式作废

## D22 当前决定
状态：并未真正废弃

## D23 是否继续保留手机号登录
后续继续讨论。

## D24 登录入口方案
为什么继续保留旧入口。

## D25 当前决定是否继续有效
仍需讨论。

## D26 当前决定是否恢复生效
需要产品和法务进一步讨论。

## D27 是否保留密码登录
候选方案：
- 继续保留密码登录
- 关闭密码登录
尚未确认。

## D28 是否保留企业登录
继续保留企业登录。
不确定。

## D29 是否保留扫码登录
仍需讨论。
结论：关闭扫码登录。

## D30 当前决定不得作废
该规则继续执行。

## ~~D31 旧决定~~
状态：禁止作废
EOF
  local out
  out=$(python3 "$CONTEXT_PACK" --repo-root "$T" --module access 2>&1) || {
    _fail "context pack should compile shared decision statuses"
    teardown_fixture
    return
  }
  if python3 -c '
import json, sys
data = json.load(sys.stdin)
statuses = {
    item["title"].split(maxsplit=1)[0].strip("~"): item["status"]
    for group in ("active", "superseded")
    for item in data["decisions"][group]
}
assert statuses["D1"] == "superseded", statuses
assert statuses["D2"] == "active", statuses
assert statuses["D3"] == "active", statuses
assert statuses["D4"] == "active", statuses
assert statuses["D5"] == "superseded", statuses
assert statuses["D6"] == "superseded", statuses
assert statuses["D7"] == "active", statuses
assert statuses["D8"] == "active", statuses
assert statuses["D9"] == "active", statuses
assert statuses["D11"] == "active", statuses
assert statuses["D12"] == "active", statuses
assert statuses["D13"] == "active", statuses
assert statuses["D14"] == "active", statuses
assert statuses["D15"] == "active", statuses
assert statuses["D16"] == "active", statuses
assert statuses["D17"] == "active", statuses
assert statuses["D19"] == "superseded", statuses
assert statuses["D21"] == "active", statuses
assert statuses["D22"] == "active", statuses
assert statuses["D29"] == "active", statuses
assert statuses["D30"] == "active", statuses
assert statuses["D31"] == "superseded", statuses
rejected = {item["title"].split(maxsplit=1)[0]: item for item in data["decisions"]["question_like_rejected"]}
assert "D10" in rejected, rejected
assert "D18" in rejected, rejected
assert "D20" in rejected, rejected
assert "D23" in rejected, rejected
assert "D24" in rejected, rejected
assert "D25" in rejected, rejected
assert "D26" in rejected, rejected
assert "D27" in rejected, rejected
assert "D28" in rejected, rejected
assert "D10" not in statuses, statuses
assert "D18" not in statuses, statuses
assert "D20" not in statuses, statuses
assert "D23" not in statuses, statuses
assert "D24" not in statuses, statuses
assert "D25" not in statuses, statuses
assert "D26" not in statuses, statuses
assert "D27" not in statuses, statuses
assert "D28" not in statuses, statuses
' <<<"$out"; then
    pass_test
  else
    _fail "context pack decision statuses diverged: $out"
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
test_context_pack_rejects_quoted_or_qualified_no_open_claims
test_context_pack_only_reports_unanswered_current_questions
test_context_pack_reports_invalid_open_question_section
test_context_pack_uses_shared_decision_status_semantics
test_context_pack_lifecycle_state_does_not_drift_approved_source
test_context_pack_includes_registered_input_evidence
report_results "context-pack"
