#!/usr/bin/env bash
# test-narrative-mode.sh
#
# 验证 M5 status-view --narrative + CLAUDE.md 章程（D-iv M1 vp-11）：
#   T1: status-view.py 含 --narrative argparse 参数
#   T2: status-view.py 含 render_narrative 函数定义
#   T3: status-view.py 含 render_banner_only 函数定义（vp-7 也验证）
#   T4: CLAUDE.md 含「Session 起始播报」章程章节（codex C-3 校准描述）
#   T5: narrative 范围降级（codex C-4）—— 不输出 commit hash / 「§四」/ 「N 天前」字串
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUS_VIEW="$REPO_ROOT/scripts/status-view.py"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"

# -----------------------------------------------------------------
# T1: --narrative argparse 参数存在
# -----------------------------------------------------------------
test_narrative_argparse_exists() {
  start_test "T1: scripts/status-view.py 含 --narrative argparse 参数"
  if ! grep -q '"--narrative"' "$STATUS_VIEW"; then
    _fail "scripts/status-view.py 缺 --narrative argparse 参数"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T2: render_narrative 函数定义
# -----------------------------------------------------------------
test_render_narrative_defined() {
  start_test "T2: scripts/status-view.py 含 render_narrative 函数定义"
  if ! grep -q "^def render_narrative" "$STATUS_VIEW"; then
    _fail "scripts/status-view.py 缺 def render_narrative"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T3: render_banner_only 函数定义（vp-7 同时验证）
# -----------------------------------------------------------------
test_render_banner_only_defined() {
  start_test "T3: scripts/status-view.py 含 render_banner_only 函数定义（vp-7）"
  if ! grep -q "^def render_banner_only" "$STATUS_VIEW"; then
    _fail "scripts/status-view.py 缺 def render_banner_only"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T4: CLAUDE.md 含「Session 起始播报」章程章节 + codex C-3 校准描述
# -----------------------------------------------------------------
test_claude_md_has_session_chapter() {
  start_test "T4: CLAUDE.md 含「Session 起始播报」章程章节 + codex C-3 校准描述"
  if ! grep -q "Session 起始播报" "$CLAUDE_MD"; then
    _fail "CLAUDE.md 缺「Session 起始播报」章节"
    return
  fi
  if ! grep -q "PM 第一条 message 后" "$CLAUDE_MD"; then
    _fail "CLAUDE.md 缺「PM 第一条 message 后」表述（codex C-3：不是「PM 一开窗口」）"
    return
  fi
  if ! grep -q "status-view.py --narrative" "$CLAUDE_MD"; then
    _fail "CLAUDE.md 缺 status-view.py --narrative 调用"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T5: narrative 范围降级（codex C-4）—— render_narrative 不含 commit hash / 「§四」/「N 天前」字串
# -----------------------------------------------------------------
test_narrative_range_descoped() {
  start_test "T5: render_narrative 不含 commit hash / 「§四」/「N 天前」（codex C-4 降级）"
  # 提取 render_narrative 函数体到下一个 def
  local body
  body=$(awk '/^def render_narrative/,/^def [a-z]/' "$STATUS_VIEW" | sed '$d')
  if echo "$body" | grep -qE '§[一二三四五六七八九十0-9]+|commit_hash|abc123|"[0-9]+ 天前"' 2>/dev/null; then
    _fail "render_narrative 含小节级 / commit hash / 相对时间字串（codex C-4 范围降级要求）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T6: render_health_check 函数定义存在
# -----------------------------------------------------------------
test_render_health_check_defined() {
  start_test "T6: status-view.py 含 render_health_check 函数定义"
  if ! grep -q "^def render_health_check" "$STATUS_VIEW"; then
    _fail "scripts/status-view.py 缺 def render_health_check"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T7: 生成器仓自身 (根有 scripts/init-project.sh) 跳过体检
# -----------------------------------------------------------------
test_health_check_skips_generator_repo() {
  start_test "T7: 生成器仓自身 (root scripts/init-project.sh) 跳过体检"
  local out
  out=$(python3 "$STATUS_VIEW" --narrative 2>&1)
  if echo "$out" | grep -q "项目体检"; then
    _fail "生成器仓不应输出体检段（应静默）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T8: 业务仓 fixture 缺 PRODUCT-RULES.md / TODO.md 时输出体检
# -----------------------------------------------------------------
test_health_check_reports_missing_docs() {
  start_test "T8: 业务仓 fixture 缺 PRODUCT-RULES.md / TODO.md 时输出体检"
  local tmp; tmp=$(mktemp -d)
  # 模拟业务仓：根无 scripts/init-project.sh，docs/ 只有 PRODUCT.md
  mkdir -p "$tmp/docs"
  echo "# PRODUCT" > "$tmp/PRODUCT.md"
  local out
  out=$(python3 "$STATUS_VIEW" --narrative "$tmp" 2>&1)
  if ! echo "$out" | grep -q "项目体检"; then
    _fail "缺 PRODUCT-RULES + TODO 时应输出体检段，实际：$out"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q "PRODUCT-RULES.md"; then
    _fail "体检应列 PRODUCT-RULES.md"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q "TODO.md"; then
    _fail "体检应列 TODO.md"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
# T9: 业务仓产品文档齐全时不输出体检（0 噪音）
# -----------------------------------------------------------------
test_health_check_silent_when_complete() {
  start_test "T9: 业务仓产品文档齐全时不输出体检（0 噪音）"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/docs"
  echo "# PRODUCT" > "$tmp/PRODUCT.md"
  echo "# PRODUCT-STATE" > "$tmp/PRODUCT-STATE.md"
  echo "# PRODUCT-RULES" > "$tmp/PRODUCT-RULES.md"
  echo "# DESIGN" > "$tmp/DESIGN.md"
  echo "# TODO" > "$tmp/TODO.md"
  local out
  out=$(python3 "$STATUS_VIEW" --narrative "$tmp" 2>&1)
  if echo "$out" | grep -q "项目体检"; then
    _fail "齐全时不应输出体检段，实际：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
# T10: 业务仓有 docs/CONTEXT.md 但无 PRODUCT.md 时提示 migrate
# -----------------------------------------------------------------
test_health_check_hints_migrate_when_context_remains() {
  start_test "T10: docs/CONTEXT.md 还在但无 PRODUCT.md 时提示 migrate"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/docs"
  echo "# CONTEXT" > "$tmp/docs/CONTEXT.md"
  local out
  out=$(python3 "$STATUS_VIEW" --narrative "$tmp" 2>&1)
  if ! echo "$out" | grep -q "migrate-context-to-project.py"; then
    _fail "应提示 migrate-context-to-project.py，实际：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------

# -----------------------------------------------------------------
# T11: 默认输出（无 flag，status skill 走这条）也输出体检段
# -----------------------------------------------------------------
test_health_check_in_default_status() {
  start_test "T11: 默认输出（status skill 入口）也输出体检"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/docs"
  echo "# PRODUCT" > "$tmp/PRODUCT.md"
  local out
  out=$(python3 "$STATUS_VIEW" "$tmp" 2>&1)
  if ! echo "$out" | grep -q "项目体检"; then
    _fail "默认分支（status 调用路径）应输出体检段，实际：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
# T12: --summary 分支也输出体检段
# -----------------------------------------------------------------
test_health_check_in_summary() {
  start_test "T12: --summary 分支也输出体检"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/docs"
  echo "# PRODUCT" > "$tmp/PRODUCT.md"
  local out
  out=$(python3 "$STATUS_VIEW" --summary "$tmp" 2>&1)
  if ! echo "$out" | grep -q "项目体检"; then
    _fail "--summary 分支应输出体检段，实际：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------

# -----------------------------------------------------------------
# T13: 未初始化目录（无 PMAI marker）直接引导 /pmai-init-project
# -----------------------------------------------------------------
test_uninitialized_project_guides_to_init() {
  start_test "T13: 未初始化目录直接引导 /pmai-init-project"
  local tmp; tmp=$(mktemp -d)
  echo "print('hello')" > "$tmp/app.py"
  local out
  out=$(python3 "$STATUS_VIEW" --narrative "$tmp" 2>&1)
  if ! echo "$out" | grep -q "还没有 PMAI 初始化"; then
    _fail "未初始化目录应提示未初始化，实际：$out"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q "/pmai-init-project"; then
    _fail "未初始化目录应引导 /pmai-init-project，实际：$out"
    rm -rf "$tmp"; return
  fi
  if echo "$out" | grep -q "/pmai-design"; then
    _fail "未初始化目录不应先引导 /pmai-design，实际：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
# T14: banner-only（design 等 skill 入口）也先引导 init
# -----------------------------------------------------------------
test_uninitialized_banner_guides_to_init() {
  start_test "T14: banner-only 未初始化时先引导 /pmai-init-project"
  local tmp; tmp=$(mktemp -d)
  local out
  out=$(python3 "$STATUS_VIEW" --banner-only --skill DESIGN "$tmp" 2>&1)
  if ! echo "$out" | grep -q "项目未初始化"; then
    _fail "banner-only 应提示项目未初始化，实际：$out"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q "/pmai-init-project"; then
    _fail "banner-only 应引导 /pmai-init-project，实际：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------
# T15: 公共 preamble 给所有 skill 暴露未初始化状态
# -----------------------------------------------------------------
test_preamble_exports_uninitialized_state() {
  start_test "T15: skill-preamble 暴露 PMAI_PROJECT_INITIALIZED=0"
  local tmp; tmp=$(mktemp -d)
  git -C "$tmp" init -q
  local out
  out=$(cd "$tmp" && PMAI_HOME="$REPO_ROOT" bash -lc 'source "$PMAI_HOME/scripts/skill-preamble.sh"' 2>&1)
  if ! echo "$out" | grep -q "PMAI_PROJECT_INITIALIZED: 0"; then
    _fail "preamble 应输出 PMAI_PROJECT_INITIALIZED: 0，实际：$out"
    rm -rf "$tmp"; return
  fi
  if ! echo "$out" | grep -q "/pmai-init-project"; then
    _fail "preamble 应引导 /pmai-init-project，实际：$out"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

test_narrative_argparse_exists
test_render_narrative_defined
test_render_banner_only_defined
test_claude_md_has_session_chapter
test_narrative_range_descoped
test_render_health_check_defined
test_health_check_skips_generator_repo
test_health_check_reports_missing_docs
test_health_check_silent_when_complete
test_health_check_hints_migrate_when_context_remains
test_health_check_in_default_status
test_health_check_in_summary
test_uninitialized_project_guides_to_init
test_uninitialized_banner_guides_to_init
test_preamble_exports_uninitialized_state

report_results "narrative-mode"
