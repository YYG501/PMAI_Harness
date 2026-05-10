#!/usr/bin/env bash
# sync-to-project.sh — 把 PM-AI-Workflow framework 全量同步到已 init 的目标项目
#
# 用法:
#   bash scripts/sync-to-project.sh <project-dir>             # 默认 dry-run，只 audit + 列差异
#   bash scripts/sync-to-project.sh <project-dir> --apply     # 真执行（不删 dst 多余）
#   bash scripts/sync-to-project.sh <project-dir> --apply --confirm-deletes  # 允许删 dst 多余
#
# Framework 同步范围（4 块）:
#   skills/    -> <project>/.claude/skills/
#   scripts/   -> <project>/.claude/scripts/
#   templates/ -> <project>/templates/
#   agents/    -> <project>/.claude/agents/
#
# 已 init 的项目用本工具做日常 framework 升级；新建项目用 init-project.sh。
# 与 init-project.sh 的区别:
#   - 不替换 {{PROJECT_NAME}}/{{PROJECT_BACKGROUND}} 占位符（不动业务实例）
#   - 不动 docs/CONTEXT.md / docs/DESIGN.md / docs/prd.md / 项目根 CLAUDE.md（这些是落地实例）
#   - 不做 git init / 端口分配 / hook 安装
#   - 仅同步 framework 资产，业务文件 PM 自维护

set -euo pipefail

# ---------- 参数解析 ----------
DRY_RUN=1
CONFIRM_DELETES=0
PROJECT_DIR=""

for arg in "$@"; do
  case "$arg" in
    --apply)            DRY_RUN=0 ;;
    --confirm-deletes)  CONFIRM_DELETES=1 ;;
    -h|--help)
      sed -n '/^# 用法:/,/^$/p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    -*)
      echo "❌ 未知参数: $arg" >&2
      exit 1
      ;;
    *)
      [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$arg" || { echo "❌ 多余位置参数: $arg" >&2; exit 1; }
      ;;
  esac
done

if [ -z "$PROJECT_DIR" ]; then
  echo "❌ 缺少必填参数 <project-dir>" >&2
  echo "   用法: bash scripts/sync-to-project.sh <project-dir> [--apply] [--confirm-deletes]" >&2
  exit 1
fi

# ---------- 路径解析 ----------
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { echo "❌ 目标项目不存在: $PROJECT_DIR" >&2; exit 1; }

# 校验：DST 必须是已 init 的项目（含 .claude/ 目录）
if [ ! -d "$DST/.claude" ]; then
  echo "❌ $DST 看起来不是已 init 的 PM-AI-Workflow 项目（缺 .claude/ 目录）" >&2
  echo "   新建项目用: bash scripts/init-project.sh" >&2
  exit 1
fi

# 校验：SRC 必须是 framework 仓
for needed in skills scripts templates agents; do
  if [ ! -d "$SRC/$needed" ]; then
    echo "❌ Framework 源不完整：缺 $SRC/$needed" >&2
    exit 1
  fi
done

echo "🔍 同步源:    $SRC"
echo "🔍 目标项目:  $DST"
echo "🔍 模式:      $([ "$DRY_RUN" = "1" ] && echo "dry-run（只 audit）" || echo "apply（真执行）")"
echo "🔍 删除策略:  $([ "$CONFIRM_DELETES" = "1" ] && echo "允许删 dst 多余文件" || echo "保留 dst 多余文件（不 --delete）")"
echo ""

# ---------- 4 块映射 ----------
# 格式: <src 子路径>:<dst 子路径>
BLOCKS=(
  "skills:.claude/skills"
  "scripts:.claude/scripts"
  "templates:templates"
  "agents:.claude/agents"
)

# init-project skill 不下发到目标项目
EXCLUDE_PATTERNS=(
  "--exclude=init-project/"
  "--exclude=init-project.sh"
)

# ---------- Step 1: Pre-sync audit ----------
echo "═══ Step 1: 预检 audit（diff -rq）═══"
HAS_DIFF=0
for block in "${BLOCKS[@]}"; do
  src_sub="${block%%:*}"
  dst_sub="${block##*:}"
  src_path="$SRC/$src_sub"
  dst_path="$DST/$dst_sub"

  echo ""
  echo "── $src_sub  →  $dst_sub ──"
  if [ ! -d "$dst_path" ]; then
    echo "  ⚠️  目标目录不存在，将整体新建"
    HAS_DIFF=1
    continue
  fi
  diff_out=$(diff -rq "$src_path" "$dst_path" 2>&1 \
    | grep -v -E "^Only.*$src_sub.*: init-project" \
    | grep -v -E "^Only.*: init-project\.sh$" \
    || true)
  if [ -z "$diff_out" ]; then
    echo "  ✅ 无差异"
  else
    echo "$diff_out" | sed 's/^/  /'
    HAS_DIFF=1
  fi
done
echo ""

if [ "$HAS_DIFF" = "0" ]; then
  echo "🎉 所有 4 块均无差异，目标项目已是最新 framework。"
  exit 0
fi

# ---------- Step 2: rsync dry-run ----------
# 用 -c（checksum）替代默认 mtime+size，避免"只是 timestamp 不同但内容一致"误报
echo "═══ Step 2: rsync 操作清单（dry-run，按内容 checksum 比较）═══"
RSYNC_OPTS=(-avnc -i)
if [ "$CONFIRM_DELETES" = "1" ]; then
  RSYNC_OPTS+=(--delete)
fi

for block in "${BLOCKS[@]}"; do
  src_sub="${block%%:*}"
  dst_sub="${block##*:}"
  src_path="$SRC/$src_sub/"
  dst_path="$DST/$dst_sub/"

  echo ""
  echo "── $src_sub  →  $dst_sub ──"
  mkdir -p "$dst_path"  # 即便 dry-run 也要确保 dst 存在以便 rsync 输出干净

  rsync "${RSYNC_OPTS[@]}" "${EXCLUDE_PATTERNS[@]}" "$src_path" "$dst_path" 2>&1 \
    | grep -E "^(\*deleting|>f|>d|<f|<d|cd)" \
    | sed 's/^/  /' \
    || echo "  ✅ 无变更"
done
echo ""

if [ "$DRY_RUN" = "1" ]; then
  echo "═══ Step 3: dry-run 完成 ═══"
  echo ""
  echo "确认无误后用 --apply 执行真同步:"
  echo "  bash scripts/sync-to-project.sh $PROJECT_DIR --apply"
  echo ""
  echo "如需删除目标侧多余文件（如废弃的 framework 资产残留）:"
  echo "  bash scripts/sync-to-project.sh $PROJECT_DIR --apply --confirm-deletes"
  exit 0
fi

# ---------- Step 3: 真执行 ----------
echo "═══ Step 3: 真执行 rsync（按内容 checksum，跳过仅 mtime 差异）═══"
RSYNC_APPLY_OPTS=(-ac)
if [ "$CONFIRM_DELETES" = "1" ]; then
  RSYNC_APPLY_OPTS+=(--delete)
fi

for block in "${BLOCKS[@]}"; do
  src_sub="${block%%:*}"
  dst_sub="${block##*:}"
  src_path="$SRC/$src_sub/"
  dst_path="$DST/$dst_sub/"

  mkdir -p "$dst_path"
  rsync "${RSYNC_APPLY_OPTS[@]}" "${EXCLUDE_PATTERNS[@]}" "$src_path" "$dst_path"
  echo "  ✅ $src_sub  →  $dst_sub  同步完成"
done

# 给 .sh 加 +x（rsync -a 会保留权限，但保险起见）
chmod +x "$DST/.claude/scripts/"*.sh 2>/dev/null || true

echo ""

# ---------- Step 4: Post-sync 复查 ----------
echo "═══ Step 4: 复查（diff -rq 验证全部对齐）═══"
RESIDUAL_DIFF=0
for block in "${BLOCKS[@]}"; do
  src_sub="${block%%:*}"
  dst_sub="${block##*:}"
  src_path="$SRC/$src_sub"
  dst_path="$DST/$dst_sub"

  diff_out=$(diff -rq "$src_path" "$dst_path" 2>&1 \
    | grep -v -E "^Only.*$src_sub.*: init-project" \
    | grep -v -E "^Only.*: init-project\.sh$" \
    || true)
  if [ -z "$diff_out" ]; then
    echo "  ✅ $src_sub  →  $dst_sub  零差异"
  else
    echo "  ⚠️  $src_sub  →  $dst_sub  仍有差异:"
    echo "$diff_out" | sed 's/^/      /'
    RESIDUAL_DIFF=1
  fi
done
echo ""

if [ "$RESIDUAL_DIFF" = "0" ]; then
  echo "🎉 同步完成且复查通过 — 4 块全部对齐 PM-AI-Workflow 主仓 framework。"
  echo ""
  echo "下一步: cd $DST && git status / git add / git commit"
else
  echo "⚠️  同步完成但复查发现残余差异（通常是 dst 有本地文件且未传 --confirm-deletes）"
  echo "    若残余文件应删除，重新跑: bash scripts/sync-to-project.sh $PROJECT_DIR --apply --confirm-deletes"
fi
