#!/usr/bin/env bash
# test-brownfield-detect.sh
#
# 验证 brownfield 检测在两层都生效（D-iv M1 vp-5a；review C-7 接口约定）：
#   T1: scripts/init-project.sh 已存在目录 → exit 非 0（脚本层；现役 line 109-113）
#   T2: scripts/init-project.sh 已存在含 .git 目录 → exit 非 0（脚本层不区分 .git/无 .git，都拒）
#   T3: skills/init-project/SKILL.md 阶段 A 含 brownfield 检测描述（skill 层）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"
INIT_PROJECT_SKILL="$REPO_ROOT/skills/init-project/SKILL.md"

# -----------------------------------------------------------------
# T1: 已存在空目录 → 拒（脚本层）
# -----------------------------------------------------------------
test_existing_empty_dir_rejected() {
  start_test "T1: init-project.sh 已存在空目录 → 拒"
  local base existing
  base=$(mktemp -d)
  existing="$base/existing-empty"
  mkdir -p "$existing"

  if bash "$INIT_PROJECT_SH" "test-proj" "$existing" "test" prototype \
       >/tmp/test-brownfield-T1.out 2>&1; then
    _fail "init-project.sh 应拒已存在目录但成功了"
    rm -rf "$base"
    return
  fi
  # 检查 stderr 含 "目标目录已存在"
  if ! grep -q "目标目录已存在" /tmp/test-brownfield-T1.out; then
    _fail "init-project.sh 退出非 0 但错误信息缺『目标目录已存在』 — /tmp/test-brownfield-T1.out"
    rm -rf "$base"
    return
  fi
  rm -rf "$base"
  pass_test
}

# -----------------------------------------------------------------
# T2: 已存在含 .git 目录 → 拒（脚本层；行为同 T1）
# -----------------------------------------------------------------
test_existing_git_dir_rejected() {
  start_test "T2: init-project.sh 已存在含 .git 目录 → 拒"
  local base existing
  base=$(mktemp -d)
  existing="$base/existing-git"
  mkdir -p "$existing/.git"

  if bash "$INIT_PROJECT_SH" "test-proj" "$existing" "test" prototype \
       >/tmp/test-brownfield-T2.out 2>&1; then
    _fail "init-project.sh 应拒已存在含 .git 目录但成功了"
    rm -rf "$base"
    return
  fi
  rm -rf "$base"
  pass_test
}

# -----------------------------------------------------------------
# T3: SKILL.md 阶段 A 含 brownfield 检测描述（skill 层 prompt 校验）
# -----------------------------------------------------------------
test_skill_describes_brownfield_gate() {
  start_test "T3: init-project SKILL.md 阶段 A 含 brownfield 检测 + /codebase-audit 引导"
  if ! grep -q "brownfield" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 不含 brownfield 描述"
    return
  fi
  if ! grep -q "/codebase-audit" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 不含 /codebase-audit 引导（brownfield 命中后应提示）"
    return
  fi
  # review C-7：两层都拦的接口约定
  if ! grep -q "两层都拦" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 缺『两层都拦』接口约定描述（review C-7）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_existing_empty_dir_rejected
test_existing_git_dir_rejected
test_skill_describes_brownfield_gate

report_results "brownfield-detect"
