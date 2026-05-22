#!/usr/bin/env bash
# init-project.sh 测试
#
# T1（静态）：skill 复制必须递归 —— 守 P1 回归
#   P1 bug：cp 非递归 glob + 2>/dev/null 吞错 → skill 的 references/ 子目录漏拷
#   （prd-writing / task-execute 都依赖 references/，新项目 init 后会丢这些引用文件）
# T2（e2e）：真跑 init-project.sh，断言生成项目含 skills/*/references/*
#   gstack 不可用时 skip（T1 已守回归）
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"

# -----------------------------------------------------------------
# T1: 静态 —— skill 复制用 cp -R、不吞错（无环境依赖，永远跑）
# -----------------------------------------------------------------
test_skill_copy_is_recursive() {
  start_test "T1: init-project.sh skill 复制递归（不漏 references/ 子目录）"
  local copy_line
  copy_line=$(grep -E 'cp .*SKILL_DIR' "$INIT_PROJECT_SH" || true)
  if [ -z "$copy_line" ]; then
    _fail "未找到 skill 复制行（grep 'cp .*SKILL_DIR'）"
    return
  fi
  if ! echo "$copy_line" | grep -q 'cp -R'; then
    _fail "skill 复制必须用 cp -R，否则 references/ 子目录漏拷 — 实际: $copy_line"
    return
  fi
  if echo "$copy_line" | grep -q '2>/dev/null'; then
    _fail "skill 复制不应 2>/dev/null 吞错误（会静默漏拷）— 实际: $copy_line"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T2: e2e —— 真跑 init-project.sh，断言 references/ 被拷贝
# -----------------------------------------------------------------
test_e2e_references_copied() {
  start_test "T2: init-project 生成项目含 skills/*/references/* 引用文件"

  # gstack 前提（同 init-project.sh）；缺则 skip，T1 已守回归
  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e（T1 静态断言已守 P1 回归）"
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

  local missing="" skill ref_dir
  for skill in prd-writing task-execute; do
    ref_dir="$proj/.claude/skills/$skill/references"
    if [ ! -d "$ref_dir" ]; then
      missing="$missing $skill/references(目录缺失)"
    elif [ -z "$(ls -A "$ref_dir" 2>/dev/null)" ]; then
      missing="$missing $skill/references(目录为空)"
    fi
  done

  # P2: 框架自用工具 measure-tthw.sh 假定框架仓根，不该分发进消费仓
  if [ -f "$proj/.claude/scripts/measure-tthw.sh" ]; then
    missing="$missing measure-tthw.sh(框架自用工具误拷进消费仓)"
  fi

  rm -rf "$base"

  if [ -n "$missing" ]; then
    _fail "生成项目漏拷 references/:$missing"
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
test_skill_copy_is_recursive
test_e2e_references_copied
test_e2e_special_chars_in_background

report_results "init-project"
