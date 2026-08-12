#!/usr/bin/env bash
# init-project.sh — 创建新业务项目
# 必须从框架仓库根目录运行
# 跑 `--help` / `-h` 看完整用法 + 期望时间

set -euo pipefail

# ---------- --help / 零参数引导 ----------
_print_help() {
  cat <<HELP
用法:
  bash scripts/init-project.sh <project-name> <target-dir> <background> [--allow-existing]

参数:
  <project-name>      业务项目名（也是 git 仓的名字）
  <target-dir>        业务项目落地路径（默认不能已存在；加 --allow-existing 可复用已有目录）
  <background>        一句话项目背景（写进生成的 CLAUDE.md）
可选 flag:
  --allow-existing    允许接住现有资料目录，但任何 PMAI 同名目标都会在写入前阻断。
                      仅当 PM 在 /pmai-init-project skill 阶段 A
                      step 3b 明确选了「资料档接住」分流时由 skill 加入；脚本本身不判断目录
                      内容是否真是非 codebase（那是 skill 层的 step 3a 代码标志扫描的责任）。
                      无同名冲突时，会先固定接入前文件路径与 hash，再由首 commit 一并保存。

期望时间:
  init-project 自身 ~10 秒（拷贝 + git init + commit）。
  跑通后先进入 Product Proposal，再由 design 形成第一个模块 spec.md。

例子:
  bash scripts/init-project.sh \\
    ExampleConsumerApp \\
    ~/Projects/ExampleConsumerApp \\
    "B 端 admin console 重构"

说明:
  本脚本是 /pmai-init-project skill 阶段 B 的骨架构建器（agent 用 Bash 调）。
  PM 主动入口走 /pmai-init-project（一气呵成 4 阶段：参数 → 骨架 → 初始背景 → Next Up）。
  本脚本也保留作非交互参数化 CLI（measure-tthw / smoke / 批量自动化依赖）。
HELP
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  _print_help
  exit 0
fi

# 解析 --allow-existing flag（位置无关）：扫所有参数挑出 flag，剩下的当位置参数
ALLOW_EXISTING=0
declare -a _POSITIONAL=()
for _arg in "$@"; do
  if [ "$_arg" = "--allow-existing" ]; then
    ALLOW_EXISTING=1
  else
    _POSITIONAL+=("$_arg")
  fi
done
# set -- 重置位置参数；空数组 fallback 防 set -u
set -- "${_POSITIONAL[@]+"${_POSITIONAL[@]}"}"

if [ $# -gt 3 ] && { [ "${4:-}" = "prototype" ] || [ "${4:-}" = "product" ]; }; then
  echo "❌ 初始化不再接收 project-type。" >&2
  echo "   请移除第 4 个参数；项目类型、技术栈和框架会在首次 /pmai-design 定稿时写入 .pm-workflow/project.yml。" >&2
  exit 2
fi

if [ $# -ne 3 ]; then
  echo "❌ 参数数量不正确（需要 <project-name> <target-dir> <background>）" >&2
  echo "   正确形态：bash scripts/init-project.sh <项目名> <落地路径> <一句话背景> [--allow-existing]" >&2
  echo "" >&2
  _print_help >&2
  exit 2
fi

PROJECT_NAME="$1"
TARGET_DIR="$2"
BACKGROUND="$3"

# 框架源路径解析顺序：
#   1. PMAI_HOME 环境变量（pmai install 后用，或 /pmai-init-project skill 显式传）
#   2. cd "$(dirname "$0")/.."（本仓 / ~/.pmai 内直接 bash scripts/init-project.sh 时）
#   3. ~/.pmai/（pmai install 默认位置兜底）
SELF_FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -n "${PMAI_HOME:-}" ] && [ -f "$PMAI_HOME/templates/CLAUDE.md.tmpl" ]; then
  FRAMEWORK_DIR="$PMAI_HOME"
elif [ -f "$SELF_FRAMEWORK_DIR/templates/CLAUDE.md.tmpl" ]; then
  FRAMEWORK_DIR="$SELF_FRAMEWORK_DIR"
elif [ -f "$HOME/.pmai/templates/CLAUDE.md.tmpl" ]; then
  FRAMEWORK_DIR="$HOME/.pmai"
else
  FRAMEWORK_DIR="$SELF_FRAMEWORK_DIR"
fi
export PMAI_HOME="$FRAMEWORK_DIR"

# --- 0. 位置 sanity check（DX I2）---
# FRAMEWORK_DIR 必须含 host entry 模板 + skills/init-project。
MISSING=""
[ -f "$FRAMEWORK_DIR/templates/CLAUDE.md.tmpl" ] || MISSING="$MISSING templates/CLAUDE.md.tmpl"
[ -f "$FRAMEWORK_DIR/templates/AGENTS.md.tmpl" ] || MISSING="$MISSING templates/AGENTS.md.tmpl"
[ -f "$FRAMEWORK_DIR/templates/codex-hooks.json.tmpl" ] || MISSING="$MISSING templates/codex-hooks.json.tmpl"
[ -d "$FRAMEWORK_DIR/skills/init-project" ] || MISSING="$MISSING skills/init-project/"
[ -f "$FRAMEWORK_DIR/scripts/install-project-hooks.sh" ] || MISSING="$MISSING scripts/install-project-hooks.sh"
if [ -n "$MISSING" ]; then
  echo "❌ 框架源缺标志文件：$MISSING" >&2
  echo "   FRAMEWORK_DIR=$FRAMEWORK_DIR" >&2
  echo "" >&2
  echo "   修复方法（任一）：" >&2
  echo "     1. pmai install                       # 全局装框架到 ~/.pmai/" >&2
  echo "     2. PMAI_HOME=/path/to/framework bash scripts/init-project.sh ..." >&2
  echo "     3. cd /path/to/PM-AI-Workflow && bash scripts/init-project.sh ..." >&2
  exit 2
fi

_require_git_identity() {
  if git var GIT_AUTHOR_IDENT >/dev/null 2>&1 \
    && git var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
    return
  fi

  echo "❌ Git 提交身份未配置，PMAI 尚未写入目标目录。" >&2
  echo "   请先配置 Git 身份：" >&2
  echo '     git config --global user.name "你的名字"' >&2
  echo '     git config --global user.email "you@example.com"' >&2
  echo "   配置后重新运行本命令。" >&2
  exit 1
}

# --- 0.5. 阻止已接入 PMAI 的目录被重复初始化 ---
_pmai_file_mentions_pmai() {
  local file="$1"
  [ -f "$file" ] || return 1
  grep -qE 'PMAI|/pmai-' "$file" 2>/dev/null
}

_pmai_target_has_project_marker() {
  [ -f "$TARGET_DIR/.pm-workflow/intake-manifest.json" ] && return 0
  [ -f "$TARGET_DIR/.opencode/commands/pmai-build.md" ] && return 0
  _pmai_file_mentions_pmai "$TARGET_DIR/AGENTS.md" && return 0
  _pmai_file_mentions_pmai "$TARGET_DIR/CLAUDE.md" && return 0
  _pmai_file_mentions_pmai "$TARGET_DIR/PRODUCT-STATE.md" && return 0
  _pmai_file_mentions_pmai "$TARGET_DIR/docs/CONTEXT.md" && return 0
  _pmai_file_mentions_pmai "$TARGET_DIR/.pm-workflow/config.yml" && return 0
  _pmai_file_mentions_pmai "$TARGET_DIR/.codex/hooks.json" && return 0
  _pmai_file_mentions_pmai "$TARGET_DIR/opencode.json" && return 0
  return 1
}

if [ -d "$TARGET_DIR" ] && _pmai_target_has_project_marker; then
  echo "❌ 目标目录已经接入 PMAI: $TARGET_DIR" >&2
  echo "   已阻止重复初始化，避免覆盖 PRODUCT.md / AGENTS.md / host 配置。" >&2
  echo "   下一步：在该目录使用 /pmai-status；需要纠正产品方向走 /pmai-proposal；框架与消费仓健康检查使用 /pmai-doctor。" >&2
  exit 1
fi

# --- c. 创建项目目录 ---
if [ -d "$TARGET_DIR" ]; then
  if [ "$ALLOW_EXISTING" = "1" ]; then
    # 资料目录可以保留原文件，但 PMAI 不接管任何同名目标。必须在第一次写入前
    # 一次列全冲突，避免初始化到一半才发现资料已被模板覆盖。
    _PMAI_INIT_CONFLICTS=()
    if [ -e "$TARGET_DIR/.pm-workflow/intake-manifest.json" ] \
      || [ -L "$TARGET_DIR/.pm-workflow/intake-manifest.json" ]; then
      _PMAI_INIT_CONFLICTS+=(".pm-workflow/intake-manifest.json")
    fi
    for _tmpl in "$FRAMEWORK_DIR/templates/"*.tmpl; do
      _basename=$(basename "$_tmpl" .tmpl)
      case "$_basename" in
        CLAUDE.md|AGENTS.md|PRODUCT.md|PRODUCT-STATE.md|DESIGN.md|PRODUCT-RULES.md|TODO.md)
          _dest="$TARGET_DIR/$_basename" ;;
        docs-INDEX.md)         _dest="$TARGET_DIR/docs/INDEX.md" ;;
        modules-INDEX.md)      _dest="$TARGET_DIR/docs/modules/INDEX.md" ;;
        engineering-INDEX.md)  _dest="$TARGET_DIR/docs/engineering/INDEX.md" ;;
        deliverables-INDEX.md) _dest="$TARGET_DIR/docs/deliverables/INDEX.md" ;;
        proposals-INDEX.md)    _dest="$TARGET_DIR/docs/proposals/INDEX.md" ;;
        settings.json)         _dest="$TARGET_DIR/.claude/settings.json" ;;
        gitignore)             _dest="$TARGET_DIR/.gitignore" ;;
        pm-workflow.config.yml) _dest="$TARGET_DIR/.pm-workflow/config.yml" ;;
        lark-publish.json)     _dest="$TARGET_DIR/templates/lark-publish.json.tmpl" ;;
        *) continue ;;
      esac
      if [ -e "$_dest" ] || [ -L "$_dest" ]; then
        _PMAI_INIT_CONFLICTS+=("${_dest#"$TARGET_DIR"/}")
      fi
    done
    if [ "${#_PMAI_INIT_CONFLICTS[@]}" -gt 0 ]; then
      echo "❌ 现有资料与 PMAI 初始化目标同名，已在写入前停止：" >&2
      for _conflict in "${_PMAI_INIT_CONFLICTS[@]}"; do
        echo "   - $_conflict" >&2
      done
      echo "   请先重命名或归档这些文件；PMAI 不会猜测如何合并现有内容。" >&2
      exit 1
    fi
    _require_git_identity
    if ! python3 "$FRAMEWORK_DIR/scripts/proposal-contract.py" \
      capture-intake "$TARGET_DIR" >/dev/null; then
      echo "❌ 无法在 PMAI 首次写入前固定接入前资料 manifest。" >&2
      echo "   初始化已停止；请处理上方不安全路径或不可读文件后重试。" >&2
      exit 1
    fi
    echo "📁 复用已存在目录: ${TARGET_DIR}（--allow-existing：资料档接住模式）"
  else
    echo "❌ 目标目录已存在: $TARGET_DIR" >&2
    echo "   修复：换一个不存在的路径，或加 --allow-existing 接住非 codebase 资料（由 /pmai-init-project skill 阶段 A step 3b 经 PM 拍板后调用）。" >&2
    exit 1
  fi
else
  _require_git_identity
  mkdir -p "$TARGET_DIR"
  echo "📁 创建项目目录: $TARGET_DIR"
fi

# --- d. 复制模板 + 替换占位符 ---
for TMPL in "$FRAMEWORK_DIR/templates/"*.tmpl; do
  BASENAME=$(basename "$TMPL" .tmpl)
  # 确定目标位置
  case "$BASENAME" in
    CLAUDE.md)              DEST="$TARGET_DIR/CLAUDE.md" ;;
    AGENTS.md)              DEST="$TARGET_DIR/AGENTS.md" ;;
    PRODUCT.md)             DEST="$TARGET_DIR/PRODUCT.md" ;;
    PRODUCT-STATE.md)       DEST="$TARGET_DIR/PRODUCT-STATE.md" ;;   # 六步项目底座：现状层 hub（下游 FORCE READ PRODUCT-STATE.md）
    docs-INDEX.md)           DEST="$TARGET_DIR/docs/INDEX.md" ;;
    DESIGN.md)              DEST="$TARGET_DIR/DESIGN.md" ;;          # 六步项目底座：正向视觉约束（build 前 AI 必读 DESIGN.md）
    PRODUCT-RULES.md)       DEST="$TARGET_DIR/PRODUCT-RULES.md" ;;
    TODO.md)                DEST="$TARGET_DIR/TODO.md" ;;
    modules-INDEX.md)       DEST="$TARGET_DIR/docs/modules/INDEX.md" ;;
    engineering-INDEX.md)   DEST="$TARGET_DIR/docs/engineering/INDEX.md" ;;
    deliverables-INDEX.md)   DEST="$TARGET_DIR/docs/deliverables/INDEX.md" ;;
    proposals-INDEX.md)      DEST="$TARGET_DIR/docs/proposals/INDEX.md" ;;
    lark-publish.json)
      # lark-publish.json: 业务实例配置，下方 f3 段独立 cp（不走主 loop 占位符替换）
  # 注：当前流程的功能型规格文档/审计模板由对应 skill 自带，不在本 loop。
      continue ;;
    settings.json)          DEST="$TARGET_DIR/.claude/settings.json" ;;
    codex-hooks.json)
      # Host hooks need merge semantics when --allow-existing reuses a repo.
      # They are installed after git init by install-project-hooks.sh.
      continue ;;
    gitignore)              DEST="$TARGET_DIR/.gitignore" ;;
    pm-workflow.config.yml) DEST="$TARGET_DIR/.pm-workflow/config.yml" ;;
    *)             continue ;;
  esac

  mkdir -p "$(dirname "$DEST")"
  # 占位符替换用 Python .replace()，不解释 replacement 元字符 —— sed 会把
  # background 里的 | 当分隔符报错、& 当「整段匹配」展开，静默污染生成文件。
  TMPL="$TMPL" DEST="$DEST" PN="$PROJECT_NAME" BG="$BACKGROUND" python3 - <<'PY'
import os
text = open(os.environ["TMPL"], encoding="utf-8").read()
text = text.replace("{{PROJECT_NAME}}", os.environ["PN"])
text = text.replace("{{PROJECT_BACKGROUND}}", os.environ["BG"])
open(os.environ["DEST"], "w", encoding="utf-8").write(text)
PY
done
echo "📋 模板已复制并替换占位符"

# --- e/f/f2/templates/hooks. I-mini 模式：消费仓 0 framework 源资产 ---
# 旧版方案 A symlink 5 块到 framework（绝对路径硬编码，跨机器 dangling）。
# I-mini：消费仓内**不放任何** framework 源资产（scripts/skills/hooks）。
# 但 Claude Code / Codex host 配置文件需要留在项目里：.claude/settings.json / .codex/hooks.json。
# skill 内部所有调用走 $PMAI_HOME/scripts/... 全局绝对路径（skill-preamble.sh 解析 PMAI_HOME）。
# pre-commit hook 内部自己 fallback PMAI_HOME=$HOME/.pmai。
# 跨机器 clone 消费仓后只需在新机器跑 pmai install → 立即可用，0 setup。
mkdir -p "$TARGET_DIR/.claude"
# 注：.claude/settings.json 已在 d 段写入；.codex/hooks.json 在 git init 后安装。

# --- f3. 业务实例配置模板（I-mini 例外）：lark-publish.json.tmpl 拷进消费仓 ---
# PM 后续要 cp templates/lark-publish.json.tmpl → .claude/lark-publish.json 并填
# 真 token —— 必须留实体在消费仓（每个项目 token 不同，~/.pmai/ 全局副本装不下
# per-project token）。
mkdir -p "$TARGET_DIR/templates"
if [ -f "$FRAMEWORK_DIR/templates/lark-publish.json.tmpl" ]; then
  cp "$FRAMEWORK_DIR/templates/lark-publish.json.tmpl" \
     "$TARGET_DIR/templates/lark-publish.json.tmpl"
fi

echo "📦 I-mini 模式：消费仓 0 framework 源资产；skill / scripts / hooks 全走 \$PMAI_HOME，项目只留 host 配置"

# --- g. settings.json 已在模板复制时创建 ---

# --- h. 创建目录结构 ---
mkdir -p "$TARGET_DIR/docs/modules"
mkdir -p "$TARGET_DIR/docs/inputs"
touch "$TARGET_DIR/docs/inputs/.gitkeep"
mkdir -p "$TARGET_DIR/docs/engineering"
mkdir -p "$TARGET_DIR/docs/deliverables"
mkdir -p "$TARGET_DIR/docs/proposals"
mkdir -p "$TARGET_DIR/docs/archive"   # 扁平：过程档案 / 一次性 review / 被取代旧文件全装这里，文件名说明为啥归档
touch "$TARGET_DIR/docs/archive/.gitkeep"
mkdir -p "$TARGET_DIR/docs/decisions"   # 项目决策档案：重大项目级"为什么这么定"，沉淀时按需冻
touch "$TARGET_DIR/docs/decisions/.gitkeep"
mkdir -p "$TARGET_DIR/.runs/events"
mkdir -p "$TARGET_DIR/.worktrees"
echo "📂 目录结构已创建"

# --- i. .gitignore 已在模板复制时创建 ---

# --- j. git init ---
cd "$TARGET_DIR"
git init -b main >/dev/null 2>&1
echo "🔀 Git 仓库已初始化（main 分支）"

# --- k1. Host hooks（I-mini：消费仓不放 hooks/ 源目录，配置指向 $HOME/.pmai/...）---
# 旧版方案 A 把 hooks/ symlink 到 framework，settings.json 用 $CLAUDE_PROJECT_DIR/hooks/...
# I-mini：消费仓 0 hook 源目录；settings.json / .codex/hooks.json 指向 $HOME/.pmai/hooks/...
if PMAI_HOME="$FRAMEWORK_DIR" bash "$FRAMEWORK_DIR/scripts/install-project-hooks.sh" 2>&1 | sed 's/^/   /'; then
  echo "🪝 Claude Code / Codex hooks 已安装"
else
  echo "⚠️  项目 hooks 安装失败（项目仍可用，PM 后续可手动跑 $HOME/.pmai/scripts/install-project-hooks.sh）" >&2
fi

# --- k2. git-hooks 模板：消费仓不放，install-hooks.sh 直接从 framework 读 ---

# --- k3. 安装 pre-commit hook（拦截非法 task 状态字段直改）---
if bash "$FRAMEWORK_DIR/scripts/install-hooks.sh" 2>&1 | sed 's/^/   /'; then
  echo "🪝 git hooks 已安装"
else
  echo "⚠️  git hooks 安装失败（项目仍可用，PM 后续可手动跑 $HOME/.pmai/scripts/install-hooks.sh）" >&2
fi

# --- l. 初始 commit ---
git add -A
if ! git commit -m "init: $PROJECT_NAME"; then
  echo "❌ 初始 commit 失败；项目文件已保留，但初始化尚未完成。" >&2
  echo "   修复上方 Git 错误后，在项目目录运行：" >&2
  echo "     git add -A" >&2
  echo "     git commit -m \"init: $PROJECT_NAME\"" >&2
  exit 1
fi
echo "📝 初始 commit 完成"

echo ""
echo "═══════════════════════════════════════"
echo "✅ 项目初始化完成: $PROJECT_NAME"
echo "📁 位置: $TARGET_DIR"
if [ "$ALLOW_EXISTING" = "1" ]; then
  echo "▶ 继续当前初始化：核验接入前资料能否作为产品基线"
  echo "   回到 /pmai-init-project；核验完成前不要进入 design 或 build。"
else
  echo "▶ Next Up: cd \"$TARGET_DIR\" && /pmai-proposal"
  echo "   先把产品用户、问题、价值、边界和 MVP 讲清楚，再进入 design。"
fi
echo "═══════════════════════════════════════"
