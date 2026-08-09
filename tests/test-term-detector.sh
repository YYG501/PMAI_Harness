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

  cp "$FRAMEWORK_ROOT/scripts/_lib/decision_status.py" "$INSTALL/scripts/_lib/decision_status.py"
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

- 状态：已废弃
- 术语：旧结算单

## D3 新定名 supersedes D2

- supersedes: D2
- 术语：新版结算单

## D4 当前定名已取代旧决定

本决定已取代 D2。
- 术语：结算凭证

## D5 旧决定状态

- 状态：superseded
- 术语：废弃结算凭证

## D6 当前决定已被取代

本决定已被取代。
- 术语：过期结算规则

## D7 当前决定被后续决定取代

- 状态：已被 D4 取代
- 术语：旧版结算规则

## D8 当前决定仍有效

本决定并未被取代。
- 术语：有效结算规则

## D9 当前决定未被取代

- 术语：未被取代的有效规则

## D10 当前决定是否被取代

- 术语：待确认取代状态的规则

## D11 旧决定已作废

- 术语：已作废规则

## D12 旧决定不再有效

- 术语：不再有效规则

## D13 Legacy decision superseded

- 术语：英文废弃规则

## D14 当前决定是否已废弃？

- 术语：待确认废弃状态的规则

## D15 当前决定是否已作废？

- 状态：已作废
- 术语：正文明确作废的规则

## D16 当前定名规则

还有更好的名字吗？
- 结论：继续使用正文问句不影响的规则。
- 术语：正文问句不影响的规则

## D17 是否统一新定名？

- 结论：统一使用已拍板问题标题规则。
- 术语：已拍板问题标题规则

## D18 当前术语是否继续有效？

- 状态：仍有效
- 术语：明确有效的问题标题规则

## D19 是否采用候选术语？

尚未确认。
- 术语：尚未确认的问题标题规则

## D20 当前术语是否继续有效？

- 状态：已作废
- 术语：正文作废的问题标题规则
MARKDOWN

  cat > "$CONSUMER/docs/modules/download-policy.md" <<'MARKDOWN'
# 下载策略

## 三、名词解释

术语 | 说明
--- | ---
下载凭证 | 一次下载授权的临时凭据
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
assert data["new_terms"] == [
    "结算批次",
    "下载凭证",
    "新版结算单",
    "结算凭证",
    "有效结算规则",
    "未被取代的有效规则",
    "正文问句不影响的规则",
    "已拍板问题标题规则",
    "明确有效的问题标题规则",
    "服务周期",
]
assert data["new_roles"] == ["平台审核员", "财务复核员", "渠道运营员"]
assert data["registered"] == ["商品池", "租户管理员"]
assert data["whitelisted"] == ["用户"]
assert data["skipped"] == ["退款窗口"]
names = {item["name"] for item in data["candidates"]}
assert "临时叫法" not in names
assert "不应从非决定段提取" not in names
assert "旧结算单" not in names
assert "废弃结算凭证" not in names
assert "过期结算规则" not in names
assert "旧版结算规则" not in names
assert "已作废规则" not in names
assert "不再有效规则" not in names
assert "英文废弃规则" not in names
assert "待确认取代状态的规则" not in names
assert "待确认废弃状态的规则" not in names
assert "正文明确作废的规则" not in names
assert "尚未确认的问题标题规则" not in names
assert "正文作废的问题标题规则" not in names
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

test_decision_status_semantics_are_linear() {
  start_test "term-detector: decision status uses linear clause assertions"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$FRAMEWORK_ROOT/scripts/_lib/term-detector.py" <<'PY'
import importlib.util
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("term_detector_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

long_replacer = "如何面向企业客户、合作伙伴，且覆盖年度综合结算的架构升级决定" * 2
cases = [
    ("negated replacement plus explicit void", "D16 当前决定未被取代但已作废", "", True),
    ("question plus explicit void", "D17 旧决定已作废，是否被 D3 取代？", "", True),
    ("proposed replacement", "D18 旧决定被提议由 D19 取代", "", False),
    ("proposed replacement in body", "D19 当前决定", "本决定已被提议由 D20 取代。", False),
    ("reactivated title", "D20 不再有效状态已解除", "", False),
    ("body already deprecated", "D21 当前决定", "本决定已经废弃。", True),
    ("body now void", "D22 当前决定", "- 状态：现已作废", True),
    ("bare void status", "D22 当前决定", "- 状态：作废", True),
    ("bare deprecated status", "D22 当前决定", "- 状态：废弃", True),
    ("long replacement name", f"D23 旧决定已被《{long_replacer}》正式取代", "", True),
    ("active decision supersedes old", "D24 新决定 supersedes D23", "", False),
    ("active decision replaced old", "D25 当前决定已取代旧决定", "", False),
    ("body names replacing decision", "D25 当前决定", "本决定已由 D3 取代。", True),
    ("markdown-list passive replacement", "D25 当前决定", "- 本决定已被 D3 取代。", True),
    ("body actively replaces old decision", "D25 当前决定", "本决定已取代 D3。", False),
    ("void current decision ignores active old version", "D25 当前决定", "本决定已作废，但旧版本仍有效。", True),
    ("active current decision ignores void old version", "D25 当前决定", "本决定仍有效，但旧版本已作废。", False),
    ("void current decision ignores active refund entry", "D25 当前决定", "本决定已作废，但退款入口仍有效。", True),
    ("implicit current subject can update status", "D25 当前决定", "本决定已作废，但仍有效。", False),
    ("question title overridden by body", "D26 当前决定是否已作废？", "- 状态：已作废", True),
    ("english body declaration", "D27 Current decision", "This decision is superseded.", True),
    ("english bare decision declaration", "D27 Current decision", "Decision is superseded.", True),
    ("english active past-tense title", "D27 New decision superseded D2", "", False),
    ("english active past-tense body", "D27 Current decision", "This decision superseded D2.", False),
    ("english passive past-tense body", "D27 Current decision", "* This decision was superseded by D2.", True),
    ("english passive title shorthand", "D27 Legacy decision superseded by D2", "", True),
    ("english modified passive body", "D27 Current decision", "This decision is now superseded by D2.", True),
    ("english nested old-decision status", "D27 Current decision", "This decision documents why D2 was superseded.", False),
    ("english perfect passive body", "D27 Current decision", "This decision has already been formally deprecated.", True),
    ("english void decision ignores active old version", "D27 Current decision", "This decision is deprecated, but the old version is still valid.", True),
    ("english active decision ignores void old version", "D27 Current decision", "This decision remains valid, but the old version is deprecated.", False),
    ("english explicit active override", "~~D27 Current decision~~", "Status: this decision is still valid", False),
    ("how-to decision explicitly void", "D28 如何处理退款的决定已作废", "", True),
    ("how-to decision parenthetical void", "D29 如何处理退款（已作废）", "", True),
    ("state question without punctuation", "D30 当前决定是否已作废", "", False),
    ("void question ending with ma", "D30 当前决定已作废吗", "", False),
    ("replacement question ending with me", "D30 当前决定已被 D2 取代么", "", False),
    ("named replacement question ending with ma", "D30 当前决定由 D2 取代嘛", "", False),
    ("void question ending with ne", "D30 当前决定已经废弃呢", "", False),
    ("bare named replacer in body", "D30 当前决定", "本决定由 D2 取代。", True),
    ("negated bare named replacer", "D30 当前决定", "本决定未由 D2 取代。", False),
    ("future bare named replacer", "D30 当前决定", "本决定将由 D2 取代。", False),
    ("english but final assertion", "D31 Current decision is not superseded but deprecated", "", True),
    ("english however final assertion", "D32 Current decision is not superseded however deprecated", "", True),
    ("english yet final assertion", "D33 Current decision is not superseded yet deprecated", "", True),
    ("discussion of a discarded option", "D34 废弃方案讨论", "", False),
    ("migration for deprecated entry", "D35 已废弃入口的迁移策略", "", False),
    ("audit rule for void order", "D36 已作废订单的审计保留规则", "", False),
    ("migration for invalid entry", "D61 不再有效入口的迁移策略", "", False),
    ("struck decision explicitly not void", "~~D37 旧决定~~", "- 状态：未作废", False),
    ("struck decision explicitly not superseded", "~~D38 旧决定~~", "- 状态：未被取代", False),
    ("normative replacement text does not reactivate", "~~D39 旧决定~~", "- 状态：不应被取代", True),
    ("struck decision explicitly not replaced by named decision", "~~D40 旧决定~~", "- 状态：未由 D2 取代", False),
    ("struck english decision explicitly not superseded", "~~D41 Old decision~~", "Status: not superseded", False),
    ("struck english decision explicitly not deprecated", "~~D42 Old decision~~", "Status: this decision is not deprecated", False),
    ("struck english decision not yet superseded", "~~D43 Old decision~~", "Status: not yet superseded", False),
    ("struck english decision not yet deprecated", "~~D44 Old decision~~", "Status: not yet deprecated", False),
    ("struck english decision never superseded", "~~D45 Old decision~~", "Status: never superseded", False),
    ("struck english decision never deprecated", "~~D46 Old decision~~", "Status: never deprecated", False),
    ("struck english decision has never been superseded", "~~D47 Old decision~~", "Status: this decision has never been superseded", False),
    ("struck english decision has not yet been deprecated", "~~D48 Old decision~~", "Status: this decision has not yet been deprecated", False),
    ("struck english decision keeps contrastive yet", "~~D49 Old decision~~", "Status: not superseded yet deprecated", True),
    ("uncertain named replacement does not reactivate", "~~D50 旧决定~~", "- 状态：可能未由 D2 取代", True),
    ("normative named replacement does not reactivate", "~~D51 旧决定~~", "- 状态：不应由 D2 取代", True),
    ("uncertain english status does not reactivate", "~~D52 Old decision~~", "Status: may not be superseded", True),
    ("normative english status does not reactivate", "~~D53 Old decision~~", "Status: should not be deprecated", True),
    ("replacement migration title is not status", "D54 被新规则取代时的迁移流程", "", False),
    ("temporal status property is not status", "D55 当前决定", "状态：被 D3 取代时保留审计记录", False),
    ("english conditional migration is not status", "D56 Migration when decision is superseded", "", False),
    ("dang conditional is not status", "D57 当本决定被 D3 取代则迁移", "", False),
    ("if conditional is not status", "D58 如果本决定被 D3 取代则迁移", "", False),
    ("ruo conditional is not status", "D59 本决定若被 D3 取代则迁移", "", False),
    ("once conditional is not status", "D60 一旦本决定被 D3 取代则迁移", "", False),
    ("formally not yet void", "D61 当前决定", "状态：尚未正式作废", False),
    ("not truly deprecated", "D62 当前决定", "状态：并未真正废弃", False),
    ("must not void is not void", "D63 当前决定不得作废", "", False),
    ("forbid voiding is not void", "D64 当前决定禁止作废", "", False),
    ("prevent voiding is not void", "D65 当前决定防止作废", "", False),
    ("normative body does not revive struck decision", "~~D66 旧决定~~", "状态：不得作废", True),
]
for name, title, body, expected in cases:
    actual = module.decision_is_superseded(title, body)
    assert actual is expected, (name, title, body, actual, expected)

question_cases = [
    (
        "body question does not reject a decision heading",
        "D62 登录入口继续有效",
        "为什么继续保留？\n结论：继续保留登录入口。",
        False,
    ),
    (
        "question heading overridden by substantive conclusion",
        "D63 是否统一邮箱登录？",
        "结论：统一采用邮箱登录。",
        False,
    ),
    (
        "question heading overridden by active status",
        "D64 当前决定是否继续有效？",
        "状态：仍有效",
        False,
    ),
    (
        "question heading overridden by superseded status",
        "D65 当前决定是否继续有效？",
        "状态：已作废",
        False,
    ),
    (
        "pure question remains rejected",
        "D66 当前决定是否继续有效？",
        "为什么要这样处理？",
        True,
    ),
    (
        "unconfirmed question remains rejected",
        "D67 当前决定是否继续有效？",
        "尚未确认。",
        True,
    ),
    (
        "body-only question remains rejected",
        "D68 登录入口方案",
        "是否保留旧入口？",
        True,
    ),
    (
        "question without punctuation remains rejected",
        "D69 是否保留旧入口",
        "为什么继续保留旧入口。",
        True,
    ),
    (
        "ongoing discussion is not a conclusion",
        "D70 是否保留旧入口",
        "后续继续讨论。",
        True,
    ),
    (
        "active-state question without punctuation",
        "D71 当前决定是否继续有效",
        "仍需讨论。",
        True,
    ),
    (
        "reactivation question without punctuation",
        "D72 当前决定是否恢复生效",
        "待定。",
        True,
    ),
    (
        "body active-state question without punctuation",
        "D73 登录入口方案",
        "当前决定是否继续有效",
        True,
    ),
    (
        "candidate actions are not a conclusion",
        "D74 是否保留旧入口",
        "候选方案：\n- 继续保留旧入口\n- 关闭旧入口",
        True,
    ),
    (
        "later unresolved text reopens a generic action",
        "D75 是否保留旧入口",
        "继续保留旧入口。\n需要产品和法务进一步讨论。",
        True,
    ),
    (
        "later formal conclusion closes an unresolved decision",
        "D76 是否保留旧入口",
        "继续保留旧入口。\n仍需讨论。\n结论：关闭旧入口。",
        False,
    ),
    ("bare undecided answer", "D77 是否保留旧入口", "待定。", True),
    ("bare uncertain answer", "D78 是否保留旧入口", "不确定。", True),
    ("bare unknown answer", "D79 是否保留旧入口", "未知。", True),
    (
        "capability description is not a refund decision",
        "D80 是否启用自动退款？",
        "当前系统支持自动退款。",
        True,
    ),
    (
        "permission description is not an account deletion decision",
        "D81 是否允许用户删除账户？",
        "系统允许删除账户。",
        True,
    ),
    (
        "english future description is not a refund decision",
        "D82 Should we enable refunds?",
        "The current system will process refunds.",
        True,
    ),
]
for name, title, body, expected in question_cases:
    actual = module.decision_is_question(title, body)
    assert actual is expected, (name, title, body, actual, expected)

neutral_title = "D99 " + ("普通标题" * 5000)
started = time.perf_counter()
assert module.decision_is_superseded(neutral_title, "") is False
elapsed = time.perf_counter() - started
assert elapsed < 1.0, ("long-title parser is not linear enough", elapsed)

question_heavy = "是否被X" * 100000
started = time.perf_counter()
assert module.is_state_question(question_heavy) is False
elapsed = time.perf_counter() - started
assert elapsed < 1.0, ("repeated state-question cues are not linear enough", elapsed)
PY
  then
    pass_test
  else
    _fail "decision status clause semantics or linearity regressed"
  fi
}

test_table_rows_stop_at_markdown_blocks() {
  start_test "term-detector: table data stops at Markdown block boundaries"
  if PYTHONDONTWRITEBYTECODE=1 python3 - "$FRAMEWORK_ROOT/scripts/_lib/term-detector.py" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("term_detector_table_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

blocks = [
    "### 后续章节 | 不是数据",
    "- 列表项 | 不是数据",
    "> 引用内容 | 不是数据",
    "```text | 不是数据",
    "    缩进代码 | 不是数据",
]
for block in blocks:
    parsed = module.tables(
        "术语 | 说明\n"
        "--- | ---\n"
        "有效术语 | 有效说明\n"
        f"{block}\n"
        "伪术语 | 不应进入上一张表\n"
    )
    assert parsed == [(["术语", "说明"], [["有效术语", "有效说明"]])], (block, parsed)
    assert module.is_table_data_row(block) is False, block

assert module.is_table_data_row("无前导竖线术语 | 正常数据") is True
assert module.is_table_data_row("| 有前导竖线术语 | 正常数据 |") is True
PY
  then
    pass_test
  else
    _fail "Markdown block content leaked into table data rows"
  fi
}

test_structured_reconciliation_uses_installed_assets
test_explicit_pmai_home_overrides_script_checkout
test_decision_status_semantics_are_linear
test_table_rows_stop_at_markdown_blocks
report_results "term-detector"
