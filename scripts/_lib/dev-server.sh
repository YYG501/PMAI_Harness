# shellcheck shell=bash
# Safe dev-server shutdown helper.
#
# A task file only stores a port, which is not ownership proof. Before killing
# a listener, verify the process cwd is inside one of the expected worktrees.

_pmaiwf_realpath_dir() {
  local p="${1:-}"
  [ -n "$p" ] && [ -d "$p" ] || return 1
  (cd "$p" && pwd -P)
}

_pmaiwf_path_under() {
  local child="$1"
  local root="$2"
  [ "$child" = "$root" ] || [[ "$child" == "$root"/* ]]
}

stop_dev_server_port() {
  local port="${1:-}"
  shift || true

  case "$port" in
    ""|*[!0-9]*)
      echo "⚠️ dev server 端口非法，跳过关闭：$port" >&2
      return 0
      ;;
  esac
  if [ "$port" -le 0 ] 2>/dev/null; then
    return 0
  fi

  local allowed_roots=()
  local root real_root
  for root in "$@"; do
    real_root=$(_pmaiwf_realpath_dir "$root" 2>/dev/null || true)
    [ -n "$real_root" ] && allowed_roots+=("$real_root")
  done

  if [ "${#allowed_roots[@]}" -eq 0 ]; then
    echo "⚠️ 未提供有效 worktree 根目录，跳过关闭端口 $port" >&2
    return 0
  fi

  local pids
  pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
  [ -n "$pids" ] || return 0

  local pid cwd real_cwd allowed stopped skipped
  stopped=0
  skipped=0
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1 || true)
    real_cwd=$(_pmaiwf_realpath_dir "$cwd" 2>/dev/null || true)
    allowed=false
    if [ -n "$real_cwd" ]; then
      for root in "${allowed_roots[@]}"; do
        if _pmaiwf_path_under "$real_cwd" "$root"; then
          allowed=true
          break
        fi
      done
    fi

    if [ "$allowed" = "true" ]; then
      kill "$pid" 2>/dev/null || true
      stopped=$((stopped + 1))
    else
      skipped=$((skipped + 1))
      echo "⚠️ 跳过端口 $port 的进程 $pid：cwd 不在当前 task/req worktree 内（cwd=${cwd:-未知}）" >&2
    fi
  done <<EOF
$pids
EOF

  if [ "$stopped" -gt 0 ]; then
    echo "🔌 已停止端口 $port 上的 dev server（$stopped 个进程）"
  fi
  if [ "$skipped" -gt 0 ]; then
    echo "⚠️ 端口 $port 有 $skipped 个监听进程因归属不明未关闭。" >&2
  fi
}
