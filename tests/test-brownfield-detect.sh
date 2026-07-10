#!/usr/bin/env bash
# test-brownfield-detect.sh
#
# 验证已有内容检测在两层都生效 + --allow-existing 资料档接住分流
# （review C-7 接口约定 + 2026-05-27 PM 反馈细化）：
#   T1: scripts/init-project.sh 已存在目录 → 默认 exit 非 0（脚本层硬拒）
#   T2: scripts/init-project.sh 已存在含 .git 目录 → 默认 exit 非 0（脚本层不区分 .git/无 .git，都拒）
#   T3: skills/init-project/SKILL.md 阶段 A 含已有代码自动分流接口
#       + 两层都拦的接口约定描述（语义断言，不依赖具体字眼）
#   T4: scripts/init-project.sh --allow-existing 空目录 → 接住（exit 0）
#   T5: scripts/init-project.sh --allow-existing 含资料目录 → 接住 + git add -A 把资料加进首 commit
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INIT_PROJECT_SH="$REPO_ROOT/scripts/init-project.sh"
INIT_PROJECT_SKILL="$REPO_ROOT/skills/init-project/SKILL.md"
DIRECTION_SKILL="$REPO_ROOT/skills/direction/SKILL.md"
CODEBASE_AUDIT_SKILL="$REPO_ROOT/skills/_internal/codebase-audit/SKILL.md"
CODEBASE_AUDIT_TMPL="$REPO_ROOT/skills/_internal/codebase-audit/templates/codebase-audit.md.tmpl"
PROJECT_QUESTIONING="$REPO_ROOT/skills/_shared/project-questioning.md"
DOCS_INDEX="$REPO_ROOT/docs/INDEX.md"
TODO_TMPL="$REPO_ROOT/templates/TODO.md.tmpl"
README="$REPO_ROOT/README.md"

# -----------------------------------------------------------------
# T1: 已存在空目录 → 拒（脚本层）
# -----------------------------------------------------------------
test_existing_empty_dir_rejected() {
  start_test "T1: init-project.sh 已存在空目录 → 拒"
  # init-project.sh 先检查 gstack 再检查目录，CI 无 gstack 时会被 gstack 检查拦下，
  # 错误信息变成「gstack 未安装」而非「目标目录已存在」。本测严格断言文案，需 gstack 可用。
  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，无法走到目录检查分支"
    return
  fi

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
# T3: SKILL.md 阶段 A 含已有内容检测语义接口（skill 层 prompt 校验）
#     语义断言，不依赖 brownfield 字眼 —— 未来字眼可换，但接口语义必须在
# -----------------------------------------------------------------
test_skill_describes_brownfield_gate() {
  start_test "T3: init-project SKILL.md 阶段 A 含已有代码自动分流 + --allow-existing 接住"
  # AI 主动诊断 + 自动分流接口（不再写死代码标志扫描，不让 PM 在 init/audit 之间选命令）
  if ! grep -qE "已有代码库|AI 主动诊断|逐条标注|manifest|Package.swift" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 不含 AI 诊断 / 已有代码识别接口"
    return
  fi
  # codebase 命中后必须自动进入子流程，而不是把另一个 skill 作为 PM 选择题抛出去
  if ! grep -qE "自动进入.*codebase-audit|内部子流程" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 不含已有代码自动进入 codebase-audit 子流程的约定"
    return
  fi
  if ! grep -q "不再问 PM" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 应明确不再问 PM 是否跑代码盘点"
    return
  fi
  if grep -qE "优先推荐.*(/pmai-codebase-audit|codebase-audit)" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 仍把 codebase-audit 写成推荐项，违背自动分流"
    return
  fi
  # 已有代码分支不能被 init-project.sh 的 gstack 硬依赖阻塞
  if ! grep -qE "不调用 .*init-project.sh|gstack 不可用不阻塞" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 缺已有代码分支不调用 init-project.sh / 不被 gstack 阻塞的约定"
    return
  fi
  if ! grep -q '.pm-workflow/config.yml:project.type' "$INIT_PROJECT_SKILL" \
     || ! grep -qE 'prototype.*product' "$CODEBASE_AUDIT_SKILL"; then
    _fail "已有代码首次接入应让 PM 确认两种项目类型并写入项目定义"
    return
  fi
  # 接住 PM 拍方案的脚本 flag 必须存在
  if ! grep -q "allow-existing" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 缺 --allow-existing flag 描述（PM 拍方案接住通路）"
    return
  fi
  # PM 明确 override 仍然可接住，但不能作为默认同级选项展示
  if ! grep -qE "PM 明确.*坚持|PM 明确.*override" "$INIT_PROJECT_SKILL"; then
    _fail "SKILL.md 缺 PM 明确 override 的接口约定"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------
# T4: --allow-existing 空目录 → 接住（exit 0）
# -----------------------------------------------------------------
test_allow_existing_empty_dir() {
  start_test "T4: init-project.sh --allow-existing 空目录 → 接住"
  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e"
    return
  fi

  local base existing
  base=$(mktemp -d)
  existing="$base/existing-empty"
  mkdir -p "$existing"

  if ! bash "$INIT_PROJECT_SH" "test-proj" "$existing" "test" prototype --allow-existing \
       >/tmp/test-brownfield-T4.out 2>&1; then
    _fail "init-project.sh --allow-existing 应接住空目录但失败 — /tmp/test-brownfield-T4.out"
    tail -20 /tmp/test-brownfield-T4.out >&2
    rm -rf "$base"
    return
  fi
  # 确认有「复用已存在目录」标志输出
  if ! grep -q "复用已存在目录" /tmp/test-brownfield-T4.out; then
    _fail "init-project.sh exit 0 但缺『复用已存在目录』标志输出"
    rm -rf "$base"
    return
  fi
  rm -rf "$base"
  pass_test
}

# -----------------------------------------------------------------
# T5: --allow-existing 含资料目录 → 接住 + git add -A 把资料加进首 commit
# -----------------------------------------------------------------
test_allow_existing_with_assets() {
  start_test "T5: init-project.sh --allow-existing 含资料 → 资料进首 commit"
  if ! command -v gstack &>/dev/null && [ ! -d "$HOME/.claude/skills/gstack" ]; then
    echo "  ⏭️  SKIP: gstack 不可用，跳过 e2e"
    return
  fi

  local base existing
  base=$(mktemp -d)
  existing="$base/existing-with-assets"
  mkdir -p "$existing"
  # 模拟 PM 的 case：放 chatgpt 导出 + DS_Store 这种非 codebase 资料
  echo '{"conversation":"sample"}' > "$existing/chatgpt-export.json"
  echo "PM 准备的项目笔记" > "$existing/notes.md"

  if ! bash "$INIT_PROJECT_SH" "test-proj" "$existing" "test" prototype --allow-existing \
       >/tmp/test-brownfield-T5.out 2>&1; then
    _fail "init-project.sh --allow-existing 应接住资料目录但失败 — /tmp/test-brownfield-T5.out"
    tail -20 /tmp/test-brownfield-T5.out >&2
    rm -rf "$base"
    return
  fi
  # 资料应保留原位
  if [ ! -f "$existing/chatgpt-export.json" ] || [ ! -f "$existing/notes.md" ]; then
    _fail "资料文件被丢失（应原位保留）"
    rm -rf "$base"
    return
  fi
  # 资料应进首 commit（git log --stat 看一下）
  if ! git -C "$existing" log --name-only --pretty=format: 2>/dev/null | grep -q "chatgpt-export.json"; then
    _fail "chatgpt-export.json 没被 git add 进首 commit"
    rm -rf "$base"
    return
  fi
  rm -rf "$base"
  pass_test
}

# -----------------------------------------------------------------
# T6: 周边入口不把已有代码首次接入重新写成手动 codebase-audit 或 direction 分类
# -----------------------------------------------------------------
test_brownfield_routing_consistent_across_docs() {
  start_test "T6: direction/docs/templates 不把首次接入指向手动 codebase-audit"

  if ! grep -q "首次起步 / 首次接入统一走 /pmai-init-project" "$DIRECTION_SKILL" \
     && ! grep -q '首次起步 / 首次接入 → 走 `/pmai-init-project`' "$DIRECTION_SKILL"; then
    _fail "direction 应说明首次接入统一走 /pmai-init-project"
    return
  fi
  if grep -qE "首次.*(/pmai-codebase-audit)" "$DIRECTION_SKILL" \
     || grep -q 'brownfield 首次接入定方向 → 走 `/pmai-codebase-audit`' "$DIRECTION_SKILL"; then
    _fail "direction 仍把已有代码首次接入指向手动 /pmai-codebase-audit"
    return
  fi
  if grep -qE "接入方向恢复|D brownfield|4 场景" "$DIRECTION_SKILL"; then
    _fail "direction 仍暴露接入恢复 / D brownfield / 四场景分类"
    return
  fi
  if ! grep -q "方向重定" "$DIRECTION_SKILL" || ! grep -q "路线规划" "$DIRECTION_SKILL"; then
    _fail "direction 应只保留方向重定 / 路线规划两类意图"
    return
  fi
  if ! grep -q "/pmai-init-project" "$DOCS_INDEX" || grep -q "里的 \`/pmai-codebase-audit\`" "$DOCS_INDEX"; then
    _fail "docs/INDEX.md 的已有代码仓入口应指向 /pmai-init-project"
    return
  fi
  if grep -q "/pmai-codebase-audit" "$README"; then
    _fail "README 不应再把 codebase-audit 暴露成公开 /pmai-* 命令"
    return
  fi
  if ! grep -q "/pmai-init-project 的首次初始化 / 已有代码接入分支" "$TODO_TMPL"; then
    _fail "TODO 模板应把首次产出口径挂到 init-project / 已有代码接入分支"
    return
  fi
  if ! grep -q "已有代码分支触发 codebase-audit 子流程" "$CODEBASE_AUDIT_TMPL"; then
    _fail "CODEBASE-AUDIT 模板应说明由 init-project 已有代码分支触发"
    return
  fi
  if ! grep -q '从 `/pmai-init-project` 的已有代码分支自动进入时，继续本流程' "$CODEBASE_AUDIT_SKILL"; then
    _fail "codebase-audit 应明确未初始化 preamble 下的 init 子流程例外"
    return
  fi
  if ! grep -q 'pmai-init-project` 已有代码分支触发的 codebase-audit step 4' "$PROJECT_QUESTIONING"; then
    _fail "_shared/project-questioning 应把 brownfield 调用方挂到 init-project 已有代码分支"
    return
  fi
  pass_test
}

# -----------------------------------------------------------------

test_existing_empty_dir_rejected
test_existing_git_dir_rejected
test_skill_describes_brownfield_gate
test_allow_existing_empty_dir
test_allow_existing_with_assets
test_brownfield_routing_consistent_across_docs

report_results "brownfield-detect"
