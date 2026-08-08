#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

setup_fixture() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/pmai-term-detector.XXXXXX")
  CONSUMER="$T/consumer"
  INSTALL="$T/install"
  MODULE="$CONSUMER/docs/modules/settlement"
  mkdir -p "$MODULE" "$INSTALL/scripts/_lib" "$INSTALL/skills/_shared/term-detector"

  cp "$FRAMEWORK_ROOT/scripts/_lib/term-detector.py" "$INSTALL/scripts/_lib/term-detector.py"
  cp "$FRAMEWORK_ROOT/skills/_shared/term-detector/whitelist.json" \
    "$INSTALL/skills/_shared/term-detector/whitelist.json"

  cat > "$CONSUMER/PRODUCT.md" <<'MARKDOWN'
# Demo

## 用户画像

| 角色 | 描述 | 关键诉求 |
| --- | --- | --- |
| 租户管理员 | 管理租户 | 管理权限 |

## 业务术语表

| 术语 | 说明 |
| --- | --- |
| 商品池 | 可供业务选择的商品集合 |
MARKDOWN

  cat > "$MODULE/spec.md" <<'MARKDOWN'
# 结算规格

普通正文里的“临时叫法”和 **重点表达** 都不是术语声明。

## 三、名词解释

| 术语 / 缩略词 | 说明 |
| --- | --- |
| 商品池 | 已登记词 |
| 结算批次 | 同一结算周期内的一组待结算订单 |
| 用户 | 通用词 |

## 五、用户与场景

### 5.1 用户角色

| 角色名 | 描述 |
| --- | --- |
| 租户管理员 | 已登记角色 |
| 平台审核员 | 审核结算批次 |
MARKDOWN

  cat > "$MODULE/decisions.md" <<'MARKDOWN'
# Decisions

## D1 术语定名

- 术语：退款窗口
- 角色：财务复核员

## 共同理由

- 术语：不应从非决定段提取

## D2 已废弃的旧定名

- 术语：旧结算单
MARKDOWN

  cat > "$CONSUMER/docs/modules/download-policy.md" <<'MARKDOWN'
# 下载策略

## 三、名词解释

| 术语 | 说明 |
| --- | --- |
| 下载凭证 | 一次下载授权的临时凭据 |
MARKDOWN

  cat > "$MODULE/discussion.md" <<'MARKDOWN'
# 讨论稿

## 名词解释

| 术语 | 说明 |
| --- | --- |
| 临时讨论名 | 尚未拍板的叫法 |
MARKDOWN

  cat > "$MODULE/.work-meta.json" <<'JSON'
{
  "build": {
    "anchor": "docs/modules/download-policy.md",
    "accepted_deltas": [
      {"kind": "term", "summary": "服务周期"},
      {"kind": "role", "summary": "渠道运营员"}
    ]
  }
}
JSON

  cat > "$MODULE/.term-skip.json" <<'JSON'
{"skipped_terms": ["退款窗口"], "skipped_roles": []}
JSON

  # A consumer-local whitelist must never override the installed framework asset.
  mkdir -p "$CONSUMER/skills/_shared/term-detector"
  cat > "$CONSUMER/skills/_shared/term-detector/whitelist.json" <<'JSON'
{"wrong_scope": ["结算批次", "平台审核员", "下载凭证"]}
JSON
}

teardown_fixture() { rm -rf "$T"; }

test_structured_reconciliation_uses_installed_assets() {
  start_test "term-detector: structured sources reconcile against installed assets and root PRODUCT"
  setup_fixture
  RESULT="$T/result.json"
  PMAI_HOME="$INSTALL" python3 "$INSTALL/scripts/_lib/term-detector.py" \
    "$MODULE" "$CONSUMER" \
    --source "docs/modules/settlement/discussion.md" \
    --work-dir "$MODULE" > "$RESULT"

  if python3 - "$RESULT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert data["new_terms"] == ["结算批次", "下载凭证", "服务周期"]
assert data["new_roles"] == ["平台审核员", "财务复核员", "渠道运营员"]
assert data["registered"] == ["商品池", "租户管理员"]
assert data["whitelisted"] == ["用户"]
assert data["skipped"] == ["退款窗口"]
names = {item["name"] for item in data["candidates"]}
assert "临时叫法" not in names
assert "不应从非决定段提取" not in names
assert "旧结算单" not in names
assert "临时讨论名" not in names
definition = next(item["definition"] for item in data["candidates"] if item["name"] == "结算批次")
assert definition == "同一结算周期内的一组待结算订单"
PY
  then
    pass_test
  else
    _fail "structured term reconciliation returned the wrong candidates"
  fi
  teardown_fixture
}

test_explicit_pmai_home_overrides_script_checkout() {
  start_test "term-detector: explicit PMAI_HOME selects framework whitelist"
  setup_fixture
  cat > "$INSTALL/skills/_shared/term-detector/whitelist.json" <<'JSON'
{"custom": ["结算批次"]}
JSON
  RESULT="$T/result.json"
  PMAI_HOME="$INSTALL" python3 "$FRAMEWORK_ROOT/scripts/_lib/term-detector.py" \
    "$MODULE" "$CONSUMER" --work-dir "$MODULE" > "$RESULT"

  if python3 - "$RESULT" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
assert "结算批次" in data["whitelisted"]
assert "结算批次" not in data["new_terms"]
PY
  then
    pass_test
  else
    _fail "explicit PMAI_HOME did not select its framework whitelist"
  fi
  teardown_fixture
}

test_structured_reconciliation_uses_installed_assets
test_explicit_pmai_home_overrides_script_checkout
report_results "term-detector"
