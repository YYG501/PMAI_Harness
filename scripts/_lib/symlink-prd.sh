# shellcheck shell=bash
# symlink-prd.sh — 在 docs/prds/ 下为 req 的 prd.md 建相对 symlink，统一 PRD 检索入口。
#
# 三类 PRD 收口位置：
#   kind=closed     -> docs/prds/<req-basename>.md        -> ../../requirements/closed/<req-basename>/prd.md
#   kind=cancelled  -> docs/prds/废弃/<req-basename>.md   -> ../../../requirements/closed/<req-basename>/prd.md
#   kind=standalone -> 由 caller 自行 ln（路径自定，见 prd-writing SKILL 步骤 0 收口段）
#
# 用法（caller 已 source 本文件）：
#   create_prd_symlink <repo-root> <req-basename> <closed|cancelled>
#
# 行为：
# - 若 closed/<req-basename>/prd.md 不存在 -> silent skip 返回 0（cancel-req 在 stage 1/2 没写 PRD 时常见）
# - 已存在同名 symlink 用 ln -sfn 覆盖（幂等，方便 close-req 重跑）
# - 已存在同名普通文件 -> 报错返回 1，避免误覆盖手工内容
# - 仅 mkdir + ln，不做 git add / commit；caller 控制 stage 时机

create_prd_symlink() {
  local repo_root="$1"
  local req_basename="$2"
  local kind="$3"

  if [ -z "$repo_root" ] || [ -z "$req_basename" ] || [ -z "$kind" ]; then
    echo "create_prd_symlink: 缺少参数 (repo_root='$repo_root' req_basename='$req_basename' kind='$kind')" >&2
    return 1
  fi

  local prd_src="$repo_root/requirements/closed/$req_basename/prd.md"
  if [ ! -f "$prd_src" ]; then
    return 0
  fi

  local link_dir link_name link_target
  case "$kind" in
    closed)
      link_dir="$repo_root/docs/prds"
      link_name="$req_basename.md"
      link_target="../../requirements/closed/$req_basename/prd.md"
      ;;
    cancelled)
      link_dir="$repo_root/docs/prds/废弃"
      link_name="$req_basename.md"
      link_target="../../../requirements/closed/$req_basename/prd.md"
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
