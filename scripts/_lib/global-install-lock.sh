#!/usr/bin/env bash
# Shared re-entrant lock for all global PMAI installation writers.

pmai_hold_global_install_lock() {
  local framework_root="$1"
  local script_path="$2"
  shift 2

  local helper="$framework_root/scripts/_lib/global_install_lock.py"
  local lock_path="${PMAI_GLOBAL_INSTALL_LOCK_PATH:-$HOME/.pmai-global-install.lock}"
  local lock_fd="${PMAI_GLOBAL_INSTALL_LOCK_FD:-}"

  if [ ! -f "$helper" ]; then
    echo "❌ 缺少全局安装锁 helper：$helper" >&2
    return 2
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "缺少 python3；请安装 Python 并加入宿主 PATH，重启宿主后重试。安装状态未修改。" >&2
    return 2
  fi

  if [ -z "$lock_fd" ]; then
    exec python3 "$helper" run --lock-path "$lock_path" -- \
      bash "$script_path" "$@"
  fi

  case "$lock_fd" in
    *[!0-9]*)
      echo "❌ 全局安装锁 fd 无效，拒绝修改安装状态。" >&2
      return 2
      ;;
  esac
  if ! python3 "$helper" verify --lock-path "$lock_path" --lock-fd "$lock_fd"; then
    echo "❌ 全局安装锁无法验证，拒绝修改安装状态。" >&2
    return 2
  fi
}
