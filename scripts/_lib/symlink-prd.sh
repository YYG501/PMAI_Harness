# shellcheck shell=bash
# symlink-prd.sh — 在 docs/prds/ 下为模块的 prd.md 建相对 symlink，统一 PRD 检索入口。
#
# PRD 源在模块文件夹 docs/modules/<模块>/prd.md（模块文件夹是长期真相源，close 后留场）。
#
# 两类 PRD 收口位置：
#   kind=closed     -> docs/prds/<模块>.md        -> ../../docs/modules/<模块>/prd.md
#   kind=cancelled  -> docs/prds/废弃/<模块>.md   -> ../../../docs/modules/<模块>/prd.md
#   kind=standalone -> 由 caller 自行 ln（路径自定，见 prd-writing SKILL 步骤 0 收口段）
#
# 用法（caller 已 source 本文件）：
#   create_prd_symlink <repo-root> <模块名> <closed|cancelled>
#
# 行为：
# - 若 docs/modules/<模块>/prd.md 不存在 -> silent skip 返回 0（cancel 在 stage 1/2 没写 PRD 时常见）
# - 已存在同名 symlink 用 ln -sfn 覆盖（幂等，方便重跑）
# - 已存在同名普通文件 -> 报错返回 1，避免误覆盖手工内容
# - 仅 mkdir + ln，不做 git add / commit；caller 控制 stage 时机

create_prd_symlink() {
  local repo_root="$1"
  local module_name="$2"
  local kind="$3"

  if [ -z "$repo_root" ] || [ -z "$module_name" ] || [ -z "$kind" ]; then
    echo "create_prd_symlink: 缺少参数 (repo_root='$repo_root' module_name='$module_name' kind='$kind')" >&2
    return 1
  fi

  local prd_src="$repo_root/docs/modules/$module_name/prd.md"
  if [ ! -f "$prd_src" ]; then
    return 0
  fi

  local link_dir link_name link_target
  case "$kind" in
    closed)
      link_dir="$repo_root/docs/prds"
      link_name="$module_name.md"
      link_target="../../docs/modules/$module_name/prd.md"
      ;;
    cancelled)
      link_dir="$repo_root/docs/prds/废弃"
      link_name="$module_name.md"
      link_target="../../../docs/modules/$module_name/prd.md"
      ;;
    *)
      echo "create_prd_symlink: 未知 kind='$kind'（允许 closed | cancelled）" >&2
      return 1
      ;;
  esac

  local link_path="$link_dir/$link_name"

  if [ -e "$link_path" ] && [ ! -L "$link_path" ]; then
    echo "create_prd_symlink: $link_path 已存在且不是 symlink，拒绝覆盖" >&2
    return 1
  fi

  mkdir -p "$link_dir"
  ln -sfn "$link_target" "$link_path"
  local rel_link="${link_path#$repo_root/}"
  echo "🔗 PRD 收口: $rel_link -> $link_target" >&2
  return 0
}
