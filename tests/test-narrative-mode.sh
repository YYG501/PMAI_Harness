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
  body=$(awk '/^def render_narrative/,/^def [a-z]/' "$STATUS_VIEW" | head -n -1)
  if echo "$body" | grep -qE '§[一二三四五六七八九十0-9]+|commit_hash|abc123|"[0-9]+ 天前"' 2>/dev/null; then
    _fail "render_narrative 含小节级 / commit hash / 相对时间字串（codex C-4 范围降级要求）"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_narrative_argparse_exists
test_render_narrative_defined
test_render_banner_only_defined
test_claude_md_has_session_chapter
test_narrative_range_descoped

report_results "narrative-mode"
