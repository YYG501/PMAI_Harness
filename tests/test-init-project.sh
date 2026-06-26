#!/usr/bin/env bash
# init-project.sh 测试（I-mini 模式 — 2026-05-26 起）
#
# I-mini 不变量：消费仓 .claude/ **不**含 framework 源资产（scripts/skills/agents/templates/hooks）。
# 所有 skill 通过全局 host skill dirs 的 pmai-* symlink 暴露（指向 $PMAI_HOME/skills/），
# skill / hook 内部调用走 $PMAI_HOME 全局路径。跨机器 clone 消费仓后只需 pmai install → 立即可用。
#
# T1（静态）：init-project.sh 不应再有 cp -R skills 等 framework 资产复制行（旧模式守反向回归）
# T2（e2e）：真跑 init-project.sh，断言生成项目 .claude/ 不含 framework 资产
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"

# -----------------------------------------------------------------
# T1: 静态 —— init-project.sh 不复制 framework 资产到消费仓（I-mini 反向回归守护）
# -----------------------------------------------------------------
test_no_framework_asset_copy() {
  start_test "T1: init-project.sh 不复制 framework 资产到消费仓（I-mini）"
  # 任何 cp -R SKILL_DIR / cp .*skills/ 都是回退到旧 cp 模式 → fail
  local bad
  bad=$(grep -nE 'cp[[:space:]]+-R.*(SKILL_DIR|FRAMEWORK_DIR/skills|FRAMEWORK_DIR/scripts|FRAMEWORK_DIR/agents)' "$INIT_PROJECT_SH" || true)
  if [ -n "$bad" ]; then
    _fail "init-project.sh 含旧 framework 资产复制行（I-mini 应 0 拷贝）— 实际：$bad"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T2: e2e —— 真跑 init-project.sh，断言生成项目 .claude/ 不含 framework 资产
# -----------------------------------------------------------------
test_e2e_no_framework_assets_in_consumer() {
  start_test "T2: init-project 生成的消费仓 .claude/ 不含 framework 资产（I-mini）"

  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e（T1 静态断言已守反向回归）"
    return
  fi

  local base proj
  base=$(mktemp -d)
  proj="$base/test-proj"

  if ! bash "$INIT_PROJECT_SH" "test-proj" "$proj" "init-project 测试" prototype \
       >/tmp/test-init-project.out 2>&1; then
    _fail "init-project.sh 执行失败 —— 见 /tmp/test-init-project.out"
    tail -20 /tmp/test-init-project.out >&2
    rm -rf "$base"
    return
  fi

  local leaked=""
  # I-mini：以下路径都不该在消费仓里
  [ -d "$proj/.claude/skills" ] && leaked="$leaked .claude/skills/"
  [ -d "$proj/.claude/scripts" ] && leaked="$leaked .claude/scripts/"
  [ -d "$proj/.claude/agents" ] && leaked="$leaked .claude/agents/"
  [ -d "$proj/.claude/templates" ] && leaked="$leaked .claude/templates/"
  # 框架自用工具不该分发到消费仓
  [ -f "$proj/.claude/scripts/measure-tthw.sh" ] && leaked="$leaked measure-tthw.sh"

  rm -rf "$base"

  if [ -n "$leaked" ]; then
    _fail "消费仓含 framework 资产泄漏（I-mini 应 0 framework）：$leaked"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T3: e2e —— background 含 sed 元字符（& | \）不污染生成文件
# -----------------------------------------------------------------
test_e2e_special_chars_in_background() {
  start_test "T3: init-project background 含 & | \\ 不污染生成的 CLAUDE.md"

  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e"
    return
  fi

  local base proj bg
  base=$(mktemp -d)
  proj="$base/test-proj"
  bg='A & B | C \ D 报表系统'

  if ! bash "$INIT_PROJECT_SH" "test-proj" "$proj" "$bg" prototype \
       >/tmp/test-init-special.out 2>&1; then
    _fail "init-project.sh 含特殊字符 background 执行失败 —— 见 /tmp/test-init-special.out"
    tail -20 /tmp/test-init-special.out >&2
    rm -rf "$base"
    return
  fi

  # 生成的 CLAUDE.md 必须原样含 background —— sed 会把 & 展开、| 当分隔符报错
  if ! grep -qF "$bg" "$proj/CLAUDE.md"; then
    _fail "CLAUDE.md 未原样包含 background（占位符替换被元字符污染）"
    rm -rf "$base"
    return
  fi

  rm -rf "$base"
  pass_test
}

# -----------------------------------------------------------------
# Run
# -----------------------------------------------------------------
test_no_framework_asset_copy
test_e2e_no_framework_assets_in_consumer
test_e2e_special_chars_in_background

report_results "init-project"
