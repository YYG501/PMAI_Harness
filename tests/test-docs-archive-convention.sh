#!/usr/bin/env bash
# test-docs-archive-convention.sh
#
# 验证消费仓根目录与 docs/ 归位约定（PM 实测踩坑修复 — example-consumer-app 顶层有错位文件）：
#   T1: templates/CLAUDE.md.tmpl 含「根目录与 docs/ 归位约定」节
#   T2: 约定含根目录项目脊柱 + docs 顶层分类清单
#   T3: 约定含顶层负面清单 + 归位规则（模块决策 → modules/；过程档案 → archive/）
#   T4: 约定含「写新文档前 AI 自问 3 题」
#   T5: init-project.sh 创建扁平 docs/archive/ 骨架 + .gitkeep
#   T6: init-project 端到端：新项目跑完后 docs/archive/ 子目录确实存在
#
# 背景：PM 实测 example-consumer-app docs/ 顶层有错位（product-principles.md /
# user-stories-permission.md 是模块决策却放顶层）+ 重复（旧 prd.md 跟 PRODUCT.md
# 重叠）+ 过程档案（PROTOTYPE_CLEANUP.md 放根目录）。framework 无约定 = AI
# 新建文档时随手放顶层 → 长期积累混乱。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_TMPL="$REPO_ROOT/templates/CLAUDE.md.tmpl"
INIT_SH="$REPO_ROOT/scripts/init-project.sh"

# -----------------------------------------------------------------
test_tmpl_has_archive_convention_section() {
  start_test "T1: CLAUDE.md.tmpl 含「根目录与 docs/ 归位约定」节"
  if ! grep -q '## 根目录与 docs/ 归位约定' "$CLAUDE_TMPL"; then
    _fail "templates/CLAUDE.md.tmpl 缺「## 根目录与 docs/ 归位约定」节"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_tmpl_has_positive_list() {
  start_test "T2: 约定含根目录项目脊柱 + docs 顶层分类清单"
  for f in AGENTS.md CLAUDE.md PRODUCT.md PRODUCT-STATE.md DESIGN.md PRODUCT-RULES.md TODO.md; do
    if ! grep -q "$f" "$CLAUDE_TMPL"; then
      _fail "约定缺根目录项目脊柱项: $f"
      return
    fi
  done
  for d in INDEX.md modules/ decisions/ inputs/ deliverables/ archive/; do
    if ! grep -q "$d" "$CLAUDE_TMPL"; then
      _fail "约定缺 docs 顶层分类项: $d"
      return
    fi
  done
  pass_test
}

# -----------------------------------------------------------------
test_tmpl_has_negative_list_and_relocation() {
  start_test "T3: 约定含负面清单 + 归位规则"
  # 提取约定段
  local section
  section=$(awk '/^## 根目录与 docs\/ 归位约定/,/^## 当前状态/' "$CLAUDE_TMPL")
  if ! echo "$section" | grep -q 'docs/modules/'; then
    _fail "约定缺「模块决策 → docs/modules/」归位规则"
    return
  fi
  if ! echo "$section" | grep -q 'docs/archive/'; then
    _fail "约定缺「过程档案 → docs/archive/」归位规则（扁平化）"
    return
  fi
  # 子目录不该再被宣传（扁平化决议）
  if echo "$section" | grep -qE 'docs/archive/(完成|旧版)'; then
    _fail "约定仍提 docs/archive/{完成,旧版} 子目录 —— 应已扁平化"
    return
  fi
  if ! echo "$section" | grep -qE '不在顶层|❌'; then
    _fail "约定缺「不在顶层」/负面清单标记"
    return
  fi
  if ! echo "$section" | grep -q '仓库根目录'; then
    _fail "约定缺主文件回仓库根目录的归位规则"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_tmpl_has_3_self_questions() {
  start_test "T4: 约定含 AI 自问 3 题"
  if ! grep -q '写新文档前 AI 自问 3 题' "$CLAUDE_TMPL"; then
    _fail "约定缺「写新文档前 AI 自问 3 题」"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_init_sh_creates_archive_dir() {
  start_test "T5: init-project.sh 创建扁平 docs/archive/ + .gitkeep"
  if ! grep -q 'mkdir -p "\$TARGET_DIR/docs/archive"' "$INIT_SH"; then
    _fail "init-project.sh 缺 docs/archive mkdir"
    return
  fi
  if ! grep -q 'touch "\$TARGET_DIR/docs/archive/.gitkeep"' "$INIT_SH"; then
    _fail "init-project.sh 缺 .gitkeep（空目录 git 跟踪需要）"
    return
  fi
  # 确认子目录不再被建（扁平化决议）
  if grep -qE 'docs/archive/(完成|旧版)' "$INIT_SH"; then
    _fail "init-project.sh 仍含 docs/archive/{完成,旧版} 子目录 mkdir —— 应已改为扁平 docs/archive/"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
test_init_e2e_archive_dir_exists() {
  start_test "T6: init-project e2e — 扁平 docs/archive/ 端到端存在"
  # init-project.sh 依赖 gstack 才走到目录创建段；CI 无 gstack 时 init 提前 fail，e2e 无意义。
  # T5 静态断言已守 init-project.sh 含归档目录创建逻辑。
  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e（T5 已守静态）"
    return
  fi

  local tmp; tmp=$(mktemp -d)
  local target="$tmp/test-archive-proj"
  if ! bash "$INIT_SH" "test-archive-proj" "$target" "test bg" prototype >/dev/null 2>&1; then
    _fail "init-project.sh 执行失败"
    rm -rf "$tmp"; return
  fi
  if [ ! -d "$target/docs/archive" ]; then
    _fail "init 后 docs/archive 目录不存在"
    rm -rf "$tmp"; return
  fi
  if [ ! -f "$target/docs/archive/.gitkeep" ]; then
    _fail "init 后 docs/archive/.gitkeep 不存在（空目录不会被 git 跟踪）"
    rm -rf "$tmp"; return
  fi
  # 子目录不该被建（扁平化决议）
  if [ -d "$target/docs/archive/完成" ] || [ -d "$target/docs/archive/旧版" ]; then
    _fail "init 后 docs/archive/{完成,旧版} 子目录仍存在 —— 应已扁平化"
    rm -rf "$tmp"; return
  fi
  rm -rf "$tmp"
  pass_test
}

# -----------------------------------------------------------------

test_tmpl_has_archive_convention_section
test_tmpl_has_positive_list
test_tmpl_has_negative_list_and_relocation
test_tmpl_has_3_self_questions
test_init_sh_creates_archive_dir
test_init_e2e_archive_dir_exists

report_results "docs-archive-convention"
