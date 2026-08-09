#!/usr/bin/env bash
# Ownership guard for the unprefixed host skill resource: skills/_shared.

# 所有公开 skill 目录都注册为宿主入口；_internal / _shared 仅供框架内部读取。
# build-close 的兼容恢复和 publish-to-lark 的明确手动发布都属于可调用用户意图，
# 是否出现在正常主路径由 PM-facing 文档控制，不通过删除宿主入口实现。
PMAI_HOST_HIDDEN_SKILLS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/host-hidden-skills.txt"

pmai_skill_is_host_exposed() {
  case "$1" in
    _internal|_shared) return 1 ;;
  esac
  [ -f "$PMAI_HOST_HIDDEN_SKILLS_FILE" ] || return 0
  ! grep -Fqx -- "$1" "$PMAI_HOST_HIDDEN_SKILLS_FILE"
}

# 旧 upgrader 可能在 fast-forward 前已把旧 rebuild_symlinks 载入进程，随后仍会
# 暴露新版已隐藏的 skill。只移除目标精确指向当前 PMAI skill 源的 symlink；
# 外来 symlink、实体目录和已删除源资产都留给 doctor 失败关闭。
pmai_prune_managed_hidden_skill_links() {
  local src_skills="$1"
  local dst_skills="$2"
  local count=0
  local skill_dir skill_name dst

  for skill_dir in "$src_skills"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    case "$skill_name" in
      _internal|_shared) continue ;;
    esac
    pmai_skill_is_host_exposed "$skill_name" && continue
    case "$skill_name" in
      pmai-*) dst="$dst_skills/$skill_name" ;;
      *)      dst="$dst_skills/pmai-$skill_name" ;;
    esac
    [ -L "$dst" ] || continue
    [ "$(readlink "$dst")" = "${skill_dir%/}" ] || continue
    rm -- "$dst" || return 1
    count=$((count + 1))
  done

  echo "$count"
}

pmai_shared_link_is_managed() {
  local src="$1"
  local dst="$2"
  [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]
}

pmai_assert_shared_link_available() {
  local src="$1"
  local dst="$2"
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    return 0
  fi
  if pmai_shared_link_is_managed "$src" "$dst"; then
    return 0
  fi
  echo "❌ $dst 已存在且不属于 PMAI，已停止以避免覆盖。" >&2
  echo "   请保留或迁移现有 _shared，再重新执行 PMAI 安装/升级。" >&2
  return 1
}

pmai_install_shared_link() {
  local src="$1"
  local dst="$2"
  pmai_assert_shared_link_available "$src" "$dst" || return 1
  if [ -L "$dst" ]; then
    rm -- "$dst"
  fi
  ln -s "$src" "$dst"
}
