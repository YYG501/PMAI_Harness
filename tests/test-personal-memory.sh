#!/usr/bin/env bash
# Personal memory stays user-level, advisory, deduplicated and fail-open.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MEMORY_SCRIPT="$REPO_ROOT/scripts/personal-memory.py"
TMP_ROOT="$(mktemp -d /tmp/pmai-personal-memory.XXXXXX)"
export PMAI_STATE_HOME="$TMP_ROOT/state"
trap 'rm -rf "$TMP_ROOT"' EXIT

json_value() {
  local expression="$1"
  python3 -c "import json,sys; data=json.load(sys.stdin); print($expression)"
}

capture_payload() {
  local payload="$1"
  printf '%s' "$payload" | python3 "$MEMORY_SCRIPT" capture --stdin
}

test_missing_store_is_fail_open() {
  start_test "T1: 缺个人经验库时 status / recall 安全返回空"
  local status recalled
  status=$(python3 "$MEMORY_SCRIPT" status 2>&1) || {
    _fail "status 不应失败：$status"
    return
  }
  recalled=$(python3 "$MEMORY_SCRIPT" recall --query "成员授权设计" 2>&1) || {
    _fail "recall 不应失败：$recalled"
    return
  }
  if [ "$(printf '%s' "$status" | json_value 'data["exists"]')" != "False" ] \
     || [ "$(printf '%s' "$recalled" | json_value 'len(data["memories"])')" != "0" ]; then
    _fail "缺库时没有返回空状态"
    return
  fi
  pass_test
}

test_capture_and_merge_personal_memory() {
  start_test "T2: 单次纠偏创建低权重经验，重复证据自动合并"
  local payload first second
  payload='{"skill":"design","signal":"explicit_correction","disposition":"personal","context_summary":"成员授权规则","failed_behavior":"只看首次建立","user_feedback":"后续新增还要逐人开通不合理","corrected_behavior":"检查对象集合变化","outcome":"接受自动适用","evidence_ref":"session:first","applies_when":"一条规则作用于会持续变化的一组对象","lesson":"检查对象新增、属性变化和离开范围后结果是否自动保持正确","reason":"避免持续重复人工","boundaries":"必须逐次判断时保留人工","cues":"规则 对象集合 成员 新增 变化 离开 授权"}'
  first=$(capture_payload "$payload") || {
    _fail "首次 capture 失败：$first"
    return
  }
  payload=${payload/session:first/session:second}
  second=$(capture_payload "$payload") || {
    _fail "重复 capture 失败：$second"
    return
  }
  if [ "$(printf '%s' "$first" | json_value 'data["action"]')" != "created" ] \
     || [ "$(printf '%s' "$first" | json_value 'data["memory"]["confidence"]')" != "0.55" ] \
     || [ "$(printf '%s' "$second" | json_value 'data["action"]')" != "merged" ] \
     || [ "$(printf '%s' "$second" | json_value 'data["memory"]["evidence_count"]')" != "2" ]; then
    _fail "创建、置信度或自动合并不符合预期"
    return
  fi
  pass_test
}

test_execution_gap_does_not_duplicate_memory() {
  start_test "T3: Skill 已覆盖但没执行时只留执行失败证据"
  local out status
  out=$(capture_payload '{"skill":"design","signal":"audit_finding","disposition":"execution_gap","context_summary":"已有提问规则","failed_behavior":"重复询问已决定事项","user_feedback":"为什么还要确认一遍","corrected_behavior":"刷新上下文后直接沿用旧决定","outcome":"停止重复提问","evidence_ref":"session:gap"}') || {
    _fail "execution gap capture 失败：$out"
    return
  }
  status=$(python3 "$MEMORY_SCRIPT" status)
  if [ "$(printf '%s' "$out" | json_value 'data["action"]')" != "recorded_execution_gap" ] \
     || [ "$(printf '%s' "$status" | json_value 'data["memories"]["active"]')" != "1" ] \
     || [ "$(printf '%s' "$status" | json_value 'data["episodes"]')" != "3" ]; then
    _fail "execution gap 误生成了个人经验或未保存证据"
    return
  fi
  pass_test
}

test_explicit_generalization_and_recall_cap() {
  start_test "T4: 明确以后都这样时高权重生效，召回硬限制最多 3 条"
  local payload out recall count confidence index applies lesson
  for index in 1 2 3 4; do
    case "$index" in
      1) applies="多个页面复用同一权限口径"; lesson="先核对各页面的可见与可改责任是否一致" ;;
      2) applies="长列表承担日常查找任务"; lesson="先核对默认筛选是否支持最高频的查找动作" ;;
      3) applies="同一数据产物会被反复导出"; lesson="先核对文件命名和版本覆盖是否能被消费方区分" ;;
      4) applies="失败动作允许用户再次尝试"; lesson="先核对重试是否会重复创建业务结果" ;;
    esac
    payload="{\"skill\":\"design\",\"signal\":\"explicit_generalization\",\"disposition\":\"personal\",\"context_summary\":\"设计共通经验 ${index}\",\"user_feedback\":\"以后都先检查 ${index}\",\"corrected_behavior\":\"增加检查 ${index}\",\"outcome\":\"已确认\",\"evidence_ref\":\"session:general-${index}\",\"applies_when\":\"${applies}\",\"lesson\":\"${lesson}\",\"reason\":\"避免遗漏 ${index}\",\"boundaries\":\"不适用其它对象 ${index}\",\"cues\":\"设计 共通 检查 ${index}\"}"
    out=$(capture_payload "$payload") || {
      _fail "第 ${index} 条明确经验写入失败：$out"
      return
    }
  done
  confidence=$(printf '%s' "$out" | json_value 'data["memory"]["confidence"]')
  recall=$(python3 "$MEMORY_SCRIPT" recall --query "设计共通检查 权限 列表 导出 失败" --limit 20)
  count=$(printf '%s' "$recall" | json_value 'len(data["memories"])')
  if [ "$confidence" != "0.9" ] || [ "$count" != "3" ]; then
    _fail "明确经验置信度应为 0.9，recall 应硬限制 3 条；实际 confidence=$confidence count=$count"
    return
  fi
  pass_test
}

test_supersede_and_forget() {
  start_test "T5: 新明确经验可取代旧经验，用户可遗忘"
  local old_id payload created new_id status forgotten
  old_id=$(python3 "$MEMORY_SCRIPT" search "对象集合新增" --limit 1 | json_value 'data["memories"][0]["id"]')
  payload="{\"skill\":\"design\",\"signal\":\"explicit_generalization\",\"disposition\":\"personal\",\"context_summary\":\"修订集合变化经验\",\"user_feedback\":\"以后先判断是否真的需要人工责任\",\"corrected_behavior\":\"先判断责任再决定自动化\",\"outcome\":\"已确认新边界\",\"evidence_ref\":\"session:supersede\",\"applies_when\":\"规则作用对象发生变化且可能需要人工责任\",\"lesson\":\"先判断变化是否需要负责人独立拍板，再决定自动更新或人工确认\",\"reason\":\"不能把所有变化都默认自动化\",\"boundaries\":\"没有业务责任的机械更新仍自动处理\",\"cues\":\"规则 对象 变化 人工责任 自动更新\",\"supersedes\":\"${old_id}\"}"
  created=$(capture_payload "$payload") || {
    _fail "supersede capture 失败：$created"
    return
  }
  new_id=$(printf '%s' "$created" | json_value 'data["memory"]["id"]')
  status=$(python3 "$MEMORY_SCRIPT" status)
  forgotten=$(python3 "$MEMORY_SCRIPT" forget "$new_id") || {
    _fail "forget 失败：$forgotten"
    return
  }
  status=$(python3 "$MEMORY_SCRIPT" status)
  if [ "$(printf '%s' "$status" | json_value 'data["memories"]["superseded"]')" != "1" ] \
     || [ "$(printf '%s' "$status" | json_value 'data["memories"]["forgotten"]')" != "1" ]; then
    _fail "取代或遗忘状态不正确"
    return
  fi
  pass_test
}

test_feedback_updates_confidence() {
  start_test "T6: 使用结果可提高或降低经验权重"
  local memory_id before after_help after_no
  memory_id=$(python3 "$MEMORY_SCRIPT" search "设计共通对象类型 1" --limit 1 | json_value 'data["memories"][0]["id"]')
  before=$(python3 "$MEMORY_SCRIPT" show "$memory_id" | json_value 'data["memory"]["confidence"]')
  after_help=$(python3 "$MEMORY_SCRIPT" feedback "$memory_id" --result helpful | json_value 'data["memory"]["confidence"]')
  after_no=$(python3 "$MEMORY_SCRIPT" feedback "$memory_id" --result not_applicable | json_value 'data["memory"]["confidence"]')
  if ! python3 -c "import sys; sys.exit(0 if float('$after_help') > float('$before') and float('$after_no') < float('$after_help') else 1)"; then
    _fail "feedback 没有按结果更新权重：before=$before helpful=$after_help not_applicable=$after_no"
    return
  fi
  pass_test
}

test_personal_memory_is_outside_context_authority() {
  start_test "T7: context pack 不读取个人经验或 PMAI_STATE_HOME"
  if grep -qE "personal-memory|PMAI_STATE_HOME|pmai-state" "$REPO_ROOT/scripts/context-pack.py"; then
    _fail "context-pack.py 不应把个人经验编入权威上下文"
    return
  fi
  if ! grep -q "不参与.*source_hash\|不参与.*项目权威 hash" "$REPO_ROOT/skills/design/SKILL.md"; then
    _fail "design 未声明个人经验不参与项目权威 hash"
    return
  fi
  pass_test
}

test_cli_exposes_optional_user_controls() {
  start_test "T8: pmai memory 提供旁路查看控制，不新增 Skill"
  local help status
  help=$(bash "$REPO_ROOT/bin/pmai" --help)
  status=$(bash "$REPO_ROOT/bin/pmai" memory status) || {
    _fail "pmai memory status 失败：$status"
    return
  }
  if ! printf '%s' "$help" | grep -q "memory" \
     || [ "$(printf '%s' "$status" | json_value 'data["exists"]')" != "True" ]; then
    _fail "CLI 未暴露 memory 或读取了错误状态目录"
    return
  fi
  pass_test
}

test_missing_store_is_fail_open
test_capture_and_merge_personal_memory
test_execution_gap_does_not_duplicate_memory
test_explicit_generalization_and_recall_cap
test_supersede_and_forget
test_feedback_updates_confidence
test_personal_memory_is_outside_context_authority
test_cli_exposes_optional_user_controls

report_results "personal-memory"
