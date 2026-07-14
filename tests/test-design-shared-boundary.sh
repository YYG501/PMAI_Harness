#!/usr/bin/env bash
# test-design-shared-boundary.sh
#
# 验证 /pmai-design 的方法论边界：
#   T1: design-only / mixed 方法文件不留在 skills/_shared/
#   T2: 现役入口不再引用 _shared/module-questioning.md 或 _shared/info-design.md
#   T3: design / spec-writing / build-close 各自引用正确真相源
#   T4: design 后台驾驶内核包含工作类型、目标绑定、事实底座和顺手动作边界
#   T5: design 直接读取提问规则并执行决策总量 / 业务转译门
#   T6: 跨模块设计只留下一个明确 build 入口，并复用未变化的 project.yml
#   T7: ready 同时固定 current source 与目标路径，build 不临时猜范围
#   T8: 长会话重读当前 skill，管理类设计检查持续运营与重复成本
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ACTIVE_SEARCH_ROOTS=(
  "$REPO_ROOT/skills"
  "$REPO_ROOT/scripts"
  "$REPO_ROOT/templates"
)

_active_hits() {
  local pattern="$1"
  grep -RInE "$pattern" "${ACTIVE_SEARCH_ROOTS[@]}" 2>/dev/null \
    | grep -v "/skills/design/references/.*-legacy\\.md" \
    | grep -v "/skill-feedback/" \
    || true
}

test_design_only_files_not_in_shared() {
  start_test "T1: design-only / mixed 方法文件不留在 _shared"
  local offenders=()
  [ -e "$REPO_ROOT/skills/_shared/module-questioning.md" ] && offenders+=("skills/_shared/module-questioning.md")
  [ -e "$REPO_ROOT/skills/_shared/info-design.md" ] && offenders+=("skills/_shared/info-design.md")
  if [ "${#offenders[@]}" -gt 0 ]; then
    _fail "以下文件不应继续留在 _shared：${offenders[*]}"
    return
  fi
  pass_test
}

test_no_active_refs_to_old_shared_design_files() {
  start_test "T2: 现役入口不再引用旧 _shared 设计方法文件"
  local hits
  hits=$(_active_hits "_shared/(module-questioning|info-design)\\.md|skills/_shared/(module-questioning|info-design)\\.md")
  if [ -n "$hits" ]; then
    _fail "发现旧 _shared 设计方法引用：$hits"
    return
  fi
  pass_test
}

test_current_truth_sources_are_wired() {
  start_test "T3: design / spec-writing / build-close 引用当前真相源"
  if ! grep -q "references/design-method.md" "$REPO_ROOT/skills/design/SKILL.md"; then
    _fail "skills/design/SKILL.md 未引用 design-method.md"
    return
  fi
  if ! grep -q "skills/_shared/pm-view/askuser-rules.md" "$REPO_ROOT/skills/design/SKILL.md"; then
    _fail "skills/design/SKILL.md 未直接引用 askuser-rules.md"
    return
  fi
  if ! grep -q "规格 4 问自检" "$REPO_ROOT/skills/spec-writing/references/writing-rules.md"; then
    _fail "spec-writing/references/writing-rules.md 缺规格 4 问自检"
    return
  fi
  if ! grep -q "skills/_shared/consistency-scan.md" "$REPO_ROOT/skills/build-close/SKILL.md"; then
    _fail "skills/build-close/SKILL.md 未显式引用 consistency-scan.md"
    return
  fi
  pass_test
}

test_design_question_convergence_is_documented() {
  start_test "T5: design 提问收敛、总量预览和业务转译已文档化"
  local skill="$REPO_ROOT/skills/design/SKILL.md"
  local method="$REPO_ROOT/skills/design/references/design-method.md"

  if ! grep -q "提问收敛门" "$skill" \
     || ! grep -q "还剩几个需要决定的问题" "$skill" \
     || ! grep -q "每次重新进入、续跑、切换主模块" "$skill"; then
    _fail "design SKILL 缺提问收敛、剩余量或续跑刷新规则"
    return
  fi
  if ! grep -q "PM 是否可以不理解实现机制" "$method" \
     || ! grep -q "当前问法立即作废" "$method" \
     || ! grep -q "同一份许可证能不能复制" "$method"; then
    _fail "design-method.md 缺业务问题转译或看不懂重问规则"
    return
  fi
  pass_test
}

test_design_cross_module_close_is_documented() {
  start_test "T6: design 跨模块收口和 project.yml 复用已文档化"
  local skill="$REPO_ROOT/skills/design/SKILL.md"
  local method="$REPO_ROOT/skills/design/references/design-method.md"

  if ! grep -q "一轮 design 只能留下一个无歧义的 build 入口" "$skill" \
     || ! grep -q "复用既有方案时文件必须完全不变" "$skill"; then
    _fail "design SKILL 缺唯一 build 入口或 project.yml 不变规则"
    return
  fi
  if ! grep -q "提供既有约束" "$method" \
     || ! grep -q "需要同步规则" "$method" \
     || ! grep -q "独立后续工作" "$method"; then
    _fail "design-method.md 缺相关模块三类归位规则"
    return
  fi
  pass_test
}

test_design_ready_handoff_is_documented() {
  start_test "T7: design/build 通过 currentness 和批准目标范围交接"
  local design="$REPO_ROOT/skills/design/SKILL.md"
  local build="$REPO_ROOT/skills/build/SKILL.md"

  if ! grep -q "TARGET_PATHS" "$design" \
     || ! grep -q -- "--context-pack" "$design" \
     || ! grep -q -- "--target-path" "$design"; then
    _fail "design SKILL 缺批准目标路径或 context pack 交接"
    return
  fi
  if ! grep -q "validate-ready" "$build" \
     || ! grep -q "check-dirty" "$build" \
     || ! grep -q "猜一个替代路径" "$build"; then
    _fail "build SKILL 缺 ready currentness、脏改动或范围复用规则"
    return
  fi
  pass_test
}

test_design_long_session_and_operations_are_documented() {
  start_test "T8: design 长会话规则新鲜度与持续运营检查已文档化"
  local skill="$REPO_ROOT/skills/design/SKILL.md"
  local method="$REPO_ROOT/skills/design/references/design-method.md"

  if ! grep -q "跨日继续、模型或主控切换、会话压缩后恢复" "$skill" \
     || ! grep -q "不能继续使用更早消息中注入的 skill 快照" "$skill" \
     || ! grep -q "两者不能互相替代" "$skill"; then
    _fail "design SKILL 缺长会话重读当前规则的硬门"
    return
  fi
  if ! grep -q "持续运营与重复成本" "$method" \
     || ! grep -q "后续对象、成员持续新增" "$method" \
     || ! grep -q "逐人重复操作" "$method" \
     || ! grep -q "不把四种场景机械变成四道确认题" "$method"; then
    _fail "design-method.md 缺持续运营、自动来源或防机械提问检查"
    return
  fi
  pass_test
}

test_design_driver_kernel_is_documented() {
  start_test "T4: /pmai-design 后台驾驶内核已文档化"
  local skill="$REPO_ROOT/skills/design/SKILL.md"
  local method="$REPO_ROOT/skills/design/references/design-method.md"

  if ! grep -q "工作类型" "$method"; then
    _fail "design-method.md 缺后台工作类型判断"
    return
  fi
  if ! grep -q "本轮目标绑定" "$method"; then
    _fail "design-method.md 缺本轮目标绑定"
    return
  fi
  if ! grep -q "冲突对齐" "$method"; then
    _fail "design-method.md 缺规格冲突对齐类型"
    return
  fi
  if ! grep -q "补齐口径" "$method"; then
    _fail "design-method.md 缺补齐未决口径类型"
    return
  fi
  if ! grep -q "不把范围越扩越大" "$method"; then
    _fail "design-method.md 缺顺手动作范围边界"
    return
  fi
  if ! grep -q "事实底座" "$method"; then
    _fail "design-method.md 缺事实底座"
    return
  fi
  if ! grep -q "当前权威口径" "$method"; then
    _fail "design-method.md 缺当前权威口径"
    return
  fi
  if ! grep -q "讨论顺序按产品结构走" "$method"; then
    _fail "design-method.md 缺产品结构推进顺序"
    return
  fi
  if ! grep -q "不要把这套后台顺序包装成" "$method"; then
    _fail "design-method.md 缺禁止固定前台模板边界"
    return
  fi
  pass_test
}

test_design_only_files_not_in_shared
test_no_active_refs_to_old_shared_design_files
test_current_truth_sources_are_wired
test_design_driver_kernel_is_documented
test_design_question_convergence_is_documented
test_design_cross_module_close_is_documented
test_design_ready_handoff_is_documented
test_design_long_session_and_operations_are_documented

report_results "design-shared-boundary"
