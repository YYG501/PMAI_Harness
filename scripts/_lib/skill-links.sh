#!/usr/bin/env bash
# Ownership guard for the unprefixed host skill resource: skills/_shared.

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
