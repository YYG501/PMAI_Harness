#!/usr/bin/env bash
# 工程结构约束 inject + double-source 双源 测试（4.5c）
#
# T11：auto-detected 标存在 → inject 写入；删标后再 inject 拒绝（保护 PM 手填）
# T12：CLAUDE.md 不含 placeholder 时 inject 返回 1（init-project 已注入过 / PM 手填）
# T13：task-spec SKILL §5 含双源冲突阻断规则
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INJECT="$REPO_ROOT/scripts/inject-structure-segment.py"
TASK_SPEC_SKILL="$REPO_ROOT/skills/task-spec/SKILL.md"
INIT_PROJECT_SKILL="$REPO_ROOT/skills/init-project/SKILL.md"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"
CLAUDE_TMPL="$REPO_ROOT/templates/CLAUDE.md.tmpl"

# Helper：从模板复制一份 CLAUDE.md 到临时目录（含 placeholder）
_copy_tmpl_with_placeholder() {
  local target="$1"
  cp "$CLAUDE_TMPL" "$target"
}

# -----------------------------------------------------------------
# T11: auto-detected 标 + 二次 inject 拒绝
# -----------------------------------------------------------------

test_t11_inject_prototype_writes_marker() {
  start_test "T11a: inject prototype → 段落含 auto-detected 标 + 派生模板内容"
  local tmp; tmp=$(mktemp -d)
  local md="$tmp/CLAUDE.md"
  _copy_tmpl_with_placeholder "$md"

  if ! python3 "$INJECT" "$md" prototype --framework-root "$REPO_ROOT" >/tmp/inject.out 2>&1; then
    _fail "inject 退出非 0"
    cat /tmp/inject.out >&2
    rm -rf "$tmp"
    return
  fi

  if ! grep -q "auto-detected: prototype" "$md"; then
    _fail "CLAUDE.md 应含 auto-detected: prototype 标"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "components/ui" "$md"; then
    _fail "CLAUDE.md 应含派生 prototype 模板内容（components/ui 等）"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_t11b_inject_framework_intent_rejected() {
  start_test "T11b: framework 档已删除，inject 应拒绝该 intent（exit 2）"
  local tmp; tmp=$(mktemp -d)
  local md="$tmp/CLAUDE.md"
  _copy_tmpl_with_placeholder "$md"

  rc=0
  python3 "$INJECT" "$md" framework --framework-root "$REPO_ROOT" >/dev/null 2>&1 || rc=$?
  if [ "$rc" == "0" ]; then
    _fail "framework 档已删除，inject 不应接受这个 intent"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_t11d_inject_unknown_writes_placeholder() {
  start_test "T11d: inject unknown → 段落含 auto-detected: unknown + 提示 PM 跑 detect"
  local tmp; tmp=$(mktemp -d)
  local md="$tmp/CLAUDE.md"
  _copy_tmpl_with_placeholder "$md"

  if ! python3 "$INJECT" "$md" unknown --framework-root "$REPO_ROOT" >/dev/null 2>&1; then
    _fail "inject unknown 退出非 0"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "auto-detected: unknown" "$md"; then
    _fail "CLAUDE.md 应含 auto-detected: unknown 标"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "detect-project-structure.py" "$md"; then
    _fail "unknown 档应提示 PM 跑 detect"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_t11c_inject_idempotent_blocks_second_call() {
  start_test "T11c: 二次 inject 拒绝（placeholder 已被替换）"
  local tmp; tmp=$(mktemp -d)
  local md="$tmp/CLAUDE.md"
  _copy_tmpl_with_placeholder "$md"
  python3 "$INJECT" "$md" system --framework-root "$REPO_ROOT" >/dev/null 2>&1

  # 二次 inject 必须拒绝
  if python3 "$INJECT" "$md" prototype --framework-root "$REPO_ROOT" >/dev/null 2>&1; then
    _fail "二次 inject 应拒绝（保护已注入内容），但成功了"
    rm -rf "$tmp"
    return
  fi
  # 内容仍是首次注入的 system，不被二次覆盖
  if ! grep -q "auto-detected: system" "$md"; then
    _fail "二次 inject 应拒绝且内容不变（应仍是 system）"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

# -----------------------------------------------------------------
# T12: PM 手填段不被覆盖
# -----------------------------------------------------------------

test_t12_pm_handfilled_segment_not_overwritten() {
  start_test "T12: PM 手填段（无 placeholder + 无 auto-detected 标）→ inject 拒绝"
  local tmp; tmp=$(mktemp -d)
  local md="$tmp/CLAUDE.md"
  cat > "$md" <<'PM_HANDFILLED'
# Test Project

## 工程结构约束

PM 手写的代码组织规则（不带框架注入标）。
- 自定义规则 1
- 自定义规则 2

## 文档位置
PM_HANDFILLED

  # 无 placeholder → inject 应返回 1（不覆盖）
  rc=0
  python3 "$INJECT" "$md" prototype --framework-root "$REPO_ROOT" >/dev/null 2>&1 || rc=$?
  if [ "$rc" != "1" ]; then
    _fail "inject 应返回 1（拒绝覆盖 PM 手填段），得 rc=$rc"
    rm -rf "$tmp"
    return
  fi
  # 内容不应被改
  if ! grep -q "PM 手写的代码组织规则" "$md"; then
    _fail "PM 手填内容应原样保留"
    rm -rf "$tmp"
    return
  fi
  if grep -q "auto-detected" "$md"; then
    _fail "inject 拒绝时不应注入任何 auto-detected 标"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

# -----------------------------------------------------------------
# T13: task-spec SKILL §5 含双源冲突阻断规则
# -----------------------------------------------------------------

test_t13_task_spec_has_dual_source_rule() {
  start_test "T13a: task-spec SKILL §5 拼接含项目级 + req 级双源说明"
  if ! grep -q "双源拼接" "$TASK_SPEC_SKILL"; then
    _fail "task-spec SKILL 应有「双源拼接」规则段（4.5c 注入）"
    return
  fi
  if ! grep -q "工程结构约束" "$TASK_SPEC_SKILL"; then
    _fail "task-spec SKILL 应引用 CLAUDE.md「工程结构约束」段"
    return
  fi
  if ! grep -q "本轮实现程度" "$TASK_SPEC_SKILL"; then
    _fail "task-spec SKILL 应引用 solution.md「本轮实现程度」字段"
    return
  fi
  pass_test
}

test_t13b_task_spec_blocks_prototype_with_full_system() {
  start_test "T13b: task-spec SKILL 含 prototype + 完整系统的双源冲突阻断规则"
  if ! grep -q "完整系统" "$TASK_SPEC_SKILL"; then
    _fail "task-spec SKILL 应描述「完整系统」的 req 级判定"
    return
  fi
  if ! grep -q "改 CLAUDE.md" "$TASK_SPEC_SKILL" || ! grep -q "改 solution.md" "$TASK_SPEC_SKILL"; then
    _fail "冲突时应给 PM 二选一指引（改 CLAUDE.md 升级 / 改 solution.md 降级）"
    return
  fi
  pass_test
}

test_t13c_task_spec_no_framework_branch() {
  start_test "T13c: task-spec SKILL §5 已移除 framework 档分支"
  # 在 §5 双源拼接段（步骤 9 内）应该不再出现 framework 档处理
  if grep -E "framework 档|framework.*跳过|跳过.*framework" "$TASK_SPEC_SKILL" >/dev/null; then
    _fail "task-spec SKILL 应已移除 framework 档分支（4.5d.1 删除）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# init-project 流程接入校验
# -----------------------------------------------------------------

test_init_project_skill_asks_intent() {
  start_test "init-project SKILL 步骤 1 询问项目意图（4 项信息）"
  if ! grep -q "项目意图" "$INIT_PROJECT_SKILL"; then
    _fail "init-project SKILL 应询问 PM「项目意图」"
    return
  fi
  # 应只列出 prototype / system / unknown 三选项（4.5d.1 删除 framework）
  for opt in "prototype" "system" "unknown"; do
    if ! grep -q "\`$opt\`" "$INIT_PROJECT_SKILL"; then
      _fail "init-project SKILL 应含 \`$opt\` 选项"
      return
    fi
  done
  if grep -q "\`framework\`" "$INIT_PROJECT_SKILL"; then
    _fail "init-project SKILL 不应再含 framework 选项（4.5d.1 删除）"
    return
  fi
  pass_test
}

test_init_project_sh_accepts_intent_arg() {
  start_test "init-project.sh 接受 4th 参数 project-intent + 校验非法值"
  # 用法 string 应含 project-intent
  if ! grep -q "project-intent" "$INIT_PROJECT_SH"; then
    _fail "init-project.sh 用法应含 project-intent"
    return
  fi
  # 应有 case 校验（4.5d.1 删除 framework，只剩 3 档）
  if ! grep -q 'prototype|system|unknown' "$INIT_PROJECT_SH"; then
    _fail "init-project.sh 应校验 intent ∈ {prototype/system/unknown}"
    return
  fi
  if grep -q 'framework|unknown\|prototype|system|framework' "$INIT_PROJECT_SH"; then
    _fail "init-project.sh case 校验不应再含 framework"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------

test_t11_inject_prototype_writes_marker
test_t11b_inject_framework_intent_rejected
test_t11c_inject_idempotent_blocks_second_call
test_t11d_inject_unknown_writes_placeholder
test_t12_pm_handfilled_segment_not_overwritten
test_t13_task_spec_has_dual_source_rule
test_t13b_task_spec_blocks_prototype_with_full_system
test_t13c_task_spec_no_framework_branch
test_init_project_skill_asks_intent
test_init_project_sh_accepts_intent_arg

report_results "inject-structure"
