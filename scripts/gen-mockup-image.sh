#!/usr/bin/env bash
# gen-mockup-image.sh — 用 codex 内置 image_gen 生成一张 UI 设计稿（mockup 图片变体）
#
# 背景 / 为什么钉版本（2026-06-22 实测定性）：
#   codex 的内置 image_gen 工具在 `codex exec` 无头模式下，**0.135.0 能正常生成并落盘**，
#   **0.141.0 回归了**（工具跑完不落盘、报 no filesystem path）。所以这里钉 0.135.0。
#   走 ChatGPT 订阅、不需要 OPENAI_API_KEY。慢（~3min/张），中文字是装饰性的（只看气质）。
#
# 设计：复制这步由本脚本干、不靠 codex agent
#   codex 把生成图存进 ~/.codex/generated_images/<session>/ig_*.png；让低推理 agent 再
#   自己 cp 到目标路径不可靠（会漏做）。所以：出图前快照 generated_images 的文件清单，
#   出图后挑"新增的那张"（按 mtime 取最新），由脚本 cp 到 --out。
#   "新增文件"本身就保证是真生成 —— codex 没法把一张旧图变成 generated_images 里的新文件，
#   所以这同时是防"拷旧图冒充"的验真（无需再比 md5）。
#
# 用法：
#   gen-mockup-image.sh --brief "<设计稿描述>" --out <相对/绝对路径.png> [--cwd <repo根>] [--codex-version 0.135.0]
#
# 单图、可组合：mockup skill 要出多版时，并行 / 后台多次调本脚本（每版一个 --out）。
#
# 退出码：0 成功（真新图已落 --out）；非 0 失败（image_gen 没产新图，已不留假图）。
set -euo pipefail

CODEX_VERSION="0.135.0"
BRIEF=""
OUT=""
CWD="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --brief)         BRIEF="$2"; shift 2 ;;
    --out)           OUT="$2"; shift 2 ;;
    --cwd)           CWD="$2"; shift 2 ;;
    --codex-version) CODEX_VERSION="$2"; shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
done

[ -n "$BRIEF" ] || { echo "缺 --brief" >&2; exit 2; }
[ -n "$OUT" ]   || { echo "缺 --out" >&2; exit 2; }

# --out 相对路径按 --cwd 解析（让图落进项目 mocks/，而非 ~/.codex/generated_images）
case "$OUT" in
  /*) OUT_ABS="$OUT" ;;
  *)  OUT_ABS="$CWD/$OUT" ;;
esac
mkdir -p "$(dirname "$OUT_ABS")"

GEN_DIR="${CODEX_HOME:-$HOME/.codex}/generated_images"
mkdir -p "$GEN_DIR"

# 列 generated_images 下所有图片（绝对路径），供前后对比
_list_gen() {
  find "$GEN_DIR" -type f \( -name '*.png' -o -name '*.webp' -o -name '*.jpg' \) 2>/dev/null | sort
}

# 1) 出图前快照：已有文件清单（事后据此找"新增的那张"）
BEFORE="$(mktemp)"; trap 'rm -f "$BEFORE"' EXIT
_list_gen > "$BEFORE" || true

# 2) prompt：只要求真生成、禁复用旧图；复制交给脚本（不依赖 agent 做）
PROMPT="用内置 image_gen 工具生成一张全新的 UI 设计稿（从头生成新像素）。

设计稿要求：
${BRIEF}

硬规则：
- 必须真正调一次 image_gen 生成新图；禁止 find / ls / cp 复用或拷贝任何已有图片文件。
- 生成即可，不必移动文件；若 image_gen 失败，打印 IMAGEGEN_FAILED 并停止。"

echo "🎨 codex@${CODEX_VERSION} 生成中（~3min）… → ${OUT}" >&2

# 3) 跑 codex（钉版本 / workspace-write / low 推理 / stdin 必须 /dev/null 否则卡死）
set +e
npx -y "@openai/codex@${CODEX_VERSION}" exec \
  --sandbox workspace-write \
  --skip-git-repo-check \
  -c model_reasoning_effort=low \
  -C "$CWD" \
  -- "$PROMPT" < /dev/null > /dev/null 2>&1
CODEX_RC=$?
set -e

# 4) 找出新增的图（出图后清单 - 出图前清单），按 mtime 取最新那张
AFTER="$(mktemp)"; _list_gen > "$AFTER" || true
NEW_FILE="$(comm -13 "$BEFORE" "$AFTER" | while read -r f; do
              [ -f "$f" ] && printf '%s\t%s\n' "$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f")" "$f"
            done | sort -rn | head -1 | cut -f2-)"
rm -f "$AFTER"

if [ -z "$NEW_FILE" ] || [ ! -s "$NEW_FILE" ]; then
  echo "❌ 失败：codex(rc=$CODEX_RC) 没在 generated_images 产出新图 —— image_gen 没成功" \
       "（确认 codex 版本=${CODEX_VERSION}、ChatGPT 已登录）" >&2
  exit 1
fi

# 5) 脚本自己复制到目标路径
cp "$NEW_FILE" "$OUT_ABS"
echo "✅ 真新图已生成: $OUT_ABS"
printf '   (源 %s)\n' "$NEW_FILE"
