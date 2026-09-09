#!/usr/bin/env bash
# Install, refresh, or check PMAI-owned Claude Code and Codex project hooks.
# User-owned settings and hook commands are preserved.

set -euo pipefail

ORIGINAL_ARGS=("$@")
MODE="install"
HOST="all"

usage() {
  cat <<'EOF'
Usage:
  install-project-hooks.sh [--check] [--host all|claude|codex]

Options:
  --check   Read-only drift check. Exit 0 when current, 1 when stale/missing.
  --host    Limit the operation to one host. Default: all.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check) MODE="check"; shift ;;
    --host)
      [ "$#" -ge 2 ] || { echo "❌ --host 缺少参数" >&2; usage >&2; exit 2; }
      HOST="$2"
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "❌ unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$HOST" in
  all|claude|codex) ;;
  *) echo "❌ --host 仅支持 all、claude、codex：$HOST" >&2; exit 2 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "❌ 当前目录不在 git 仓内。请在项目根目录运行。" >&2
  exit 2
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PMAI_HOME="${PMAI_HOME:-}"
if [ -z "$PMAI_HOME" ]; then
  if [ -f "$SCRIPT_DIR/../templates/codex-hooks.json.tmpl" ]; then
    PMAI_HOME="$(cd "$SCRIPT_DIR/.." && pwd)"
  else
    PMAI_HOME="$HOME/.pmai"
  fi
fi
if [ ! -d "$PMAI_HOME" ]; then
  echo "❌ PMAI_HOME 不存在或不是目录：$PMAI_HOME" >&2
  exit 2
fi
PMAI_HOME="$(cd "$PMAI_HOME" && pwd -P)"
ATOMIC_FILE="$SCRIPT_DIR/_lib/atomic_file.py"
if [ ! -f "$ATOMIC_FILE" ]; then
  echo "❌ 缺少原子文件写入 helper：$ATOMIC_FILE" >&2
  exit 2
fi

# The lock is intentionally permanent inside this worktree's Git directory.
# It serializes cooperative PMAI writers; it is not a security boundary against
# a non-cooperative process running as the same OS user.
GIT_DIR="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
if [ -z "$GIT_DIR" ] || [ ! -d "$GIT_DIR" ]; then
  echo "❌ 无法定位当前仓库的 Git 目录，拒绝检查或刷新 Host 配置。" >&2
  exit 2
fi
GIT_DIR="$(cd "$GIT_DIR" && pwd -P)"
LOCK_PATH="$GIT_DIR/.pmai-install-project-hooks.lock"

if [ "$MODE" = "check" ]; then
  if ! LOCK_STATE="$(python3 "$ATOMIC_FILE" lock-status \
    --lock-path "$LOCK_PATH")"; then
    echo "⚠️  Host 配置协作锁状态无法安全确认，按漂移处理。" >&2
    exit 1
  fi
  if [ "$LOCK_STATE" = "busy" ]; then
    echo "⚠️  另一 PMAI 安装器正在刷新 Host 配置，当前检查按漂移处理。" >&2
    exit 1
  fi
  if [ "$LOCK_STATE" != "idle" ]; then
    echo "⚠️  Host 配置协作锁返回未知状态，按漂移处理。" >&2
    exit 1
  fi
elif [ -z "${PMAI_PROJECT_HOOKS_LOCK_FD:-}" ]; then
  if [ ! -d "$GIT_DIR" ]; then
    echo "❌ Git 目录在获取协作锁前消失，拒绝刷新 Host 配置。" >&2
    exit 2
  fi
  exec python3 "$ATOMIC_FILE" run-locked \
    --lock-path "$LOCK_PATH" -- \
    bash "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" \
      ${ORIGINAL_ARGS[@]+"${ORIGINAL_ARGS[@]}"}
else
  case "$PMAI_PROJECT_HOOKS_LOCK_FD" in
    ''|*[!0-9]*)
      echo "❌ Host 配置协作锁 fd 无效，拒绝刷新。" >&2
      exit 2
      ;;
  esac
  if ! python3 "$ATOMIC_FILE" verify-lock-fd \
    --lock-path "$LOCK_PATH" \
    --lock-fd "$PMAI_PROJECT_HOOKS_LOCK_FD"; then
    echo "❌ Host 配置协作锁 fd 无法验证，拒绝刷新。" >&2
    exit 2
  fi
fi

TMP_FILES=()
TX_LABELS=()
TX_DESTS=()
TX_DISPLAY_DESTS=()
TX_PARENTS=()
TX_DEST_NAMES=()
TX_PARENT_FDS=()
TX_PARENT_DEVICES=()
TX_PARENT_INODES=()
TX_STAGES=()
TX_STAGE_DEVICES=()
TX_STAGE_INODES=()
TX_STAGE_SIZES=()
TX_STAGE_MTIMES_NS=()
TX_EXISTED=()
TX_MODES=()
TX_BACKUPS=()
TX_BACKUP_DEVICES=()
TX_BACKUP_INODES=()
TX_BACKUP_SIZES=()
TX_BACKUP_MTIMES_NS=()
TX_ORIGINAL_DEVICES=()
TX_ORIGINAL_INODES=()
TX_ORIGINAL_SIZES=()
TX_ORIGINAL_MTIMES_NS=()
TX_RENDERED=()
TX_COUNT=0
TX_STARTED=0
TX_COMPLETE=0
TX_COMMITTED_COUNT=0
TX_ROLLBACK_OK=0

canonical_repo_destination() {
  local path="$1"

  python3 - "$REPO_ROOT" "$path" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve(strict=True)
destination = Path(os.path.realpath(sys.argv[2]))
try:
    relative = destination.relative_to(root)
except ValueError:
    raise SystemExit(1)
if not relative.parts:
    raise SystemExit(1)
print(destination)
PY
}

open_parent_fd() {
  local fd="$1"
  local parent="$2"

  case "$fd" in
    7) exec 7<"$parent" ;;
    8) exec 8<"$parent" ;;
    *) echo "❌ 内部错误：不支持的 Host 目录 fd：$fd" >&2; return 2 ;;
  esac
}

atomic_at() {
  local fd="$1"
  local device="$2"
  local inode="$3"
  local parent="$4"
  local command="$5"
  shift 5

  python3 "$ATOMIC_FILE" "$command" \
    --directory-fd "$fd" \
    --expected-device "$device" \
    --expected-inode "$inode" \
    --parent-display "$parent" \
    "$@"
}

is_decimal_identity() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

display_destination_is_bound() {
  local display_path="$1"
  local expected_path="$2"
  local resolved

  resolved="$(canonical_repo_destination "$display_path" 2>/dev/null || true)"
  [ "$resolved" = "$expected_path" ]
}

rollback_transaction() {
  local index display_dest parent dest_name fd device inode backup rendered state failed

  failed=0
  echo "⚠️  Host 配置写入未完成，正在回滚已更新文件。" >&2
  index=$((TX_COMMITTED_COUNT - 1))
  while [ "$index" -ge 0 ]; do
    display_dest="${TX_DISPLAY_DESTS[$index]}"
    parent="${TX_PARENTS[$index]}"
    dest_name="${TX_DEST_NAMES[$index]}"
    fd="${TX_PARENT_FDS[$index]}"
    device="${TX_PARENT_DEVICES[$index]}"
    inode="${TX_PARENT_INODES[$index]}"
    rendered="${TX_RENDERED[$index]}"

    if [ "${TX_EXISTED[$index]}" = "1" ]; then
      backup="${TX_BACKUPS[$index]}"
      state="$(atomic_at "$fd" "$device" "$inode" "$parent" inspect-at \
        --destination-name "$dest_name" \
        --destination-device "${TX_ORIGINAL_DEVICES[$index]}" \
        --destination-inode "${TX_ORIGINAL_INODES[$index]}" \
        --destination-size "${TX_ORIGINAL_SIZES[$index]}" \
        --destination-mtime-ns "${TX_ORIGINAL_MTIMES_NS[$index]}" \
        --expected-name "$backup" \
        --expected-entry-device "${TX_BACKUP_DEVICES[$index]}" \
        --expected-entry-inode "${TX_BACKUP_INODES[$index]}" \
        --expected-entry-size "${TX_BACKUP_SIZES[$index]}" \
        --expected-entry-mtime-ns "${TX_BACKUP_MTIMES_NS[$index]}" \
        --expected-mode "${TX_MODES[$index]}" 2>/dev/null || true)"
      if [ "$state" = "same" ]; then
        # The attempted rename did not replace this destination.
        :
      else
        state="$(atomic_at "$fd" "$device" "$inode" "$parent" inspect-at \
          --destination-name "$dest_name" \
          --destination-device "${TX_STAGE_DEVICES[$index]}" \
          --destination-inode "${TX_STAGE_INODES[$index]}" \
          --destination-size "${TX_STAGE_SIZES[$index]}" \
          --destination-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}" \
          --expected-path "$rendered" \
          --expected-mode "${TX_MODES[$index]}" 2>/dev/null || true)"
        if [ "$state" = "same" ]; then
          if ! atomic_at "$fd" "$device" "$inode" "$parent" replace-at \
            --destination-name "$dest_name" \
            --destination-device "${TX_STAGE_DEVICES[$index]}" \
            --destination-inode "${TX_STAGE_INODES[$index]}" \
            --destination-size "${TX_STAGE_SIZES[$index]}" \
            --destination-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}" \
            --staged-name "$backup" \
            --staged-device "${TX_BACKUP_DEVICES[$index]}" \
            --staged-inode "${TX_BACKUP_INODES[$index]}" \
            --staged-size "${TX_BACKUP_SIZES[$index]}" \
            --staged-mtime-ns "${TX_BACKUP_MTIMES_NS[$index]}" \
            --expected-path "$rendered" \
            --expected-mode "${TX_MODES[$index]}"; then
            echo "❌ 回滚失败，原配置备份保留在：$parent/$backup" >&2
            failed=1
          fi
        else
          echo "❌ 回滚停止：${display_dest} 已被其它进程修改，未覆盖并发内容；原配置备份保留在：$parent/$backup" >&2
          failed=1
        fi
      fi
    else
      state="$(atomic_at "$fd" "$device" "$inode" "$parent" inspect-at \
        --destination-name "$dest_name" \
        --destination-device "${TX_STAGE_DEVICES[$index]}" \
        --destination-inode "${TX_STAGE_INODES[$index]}" \
        --destination-size "${TX_STAGE_SIZES[$index]}" \
        --destination-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}" \
        --expected-path "$rendered" \
        --expected-mode "${TX_MODES[$index]}" 2>/dev/null || true)"
      if [ "$state" = "missing" ]; then
        # The attempted rename did not create this destination.
        :
      elif [ "$state" = "same" ]; then
        if ! atomic_at "$fd" "$device" "$inode" "$parent" delete-at \
          --destination-name "$dest_name" \
          --destination-device "${TX_STAGE_DEVICES[$index]}" \
          --destination-inode "${TX_STAGE_INODES[$index]}" \
          --destination-size "${TX_STAGE_SIZES[$index]}" \
          --destination-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}" \
          --expected-path "$rendered" \
          --expected-mode "${TX_MODES[$index]}"; then
          echo "❌ 回滚失败，无法删除本轮新建配置：$parent/$dest_name" >&2
          failed=1
        fi
      else
        echo "❌ 回滚停止：${display_dest} 已被其它进程修改，未删除并发内容。" >&2
        failed=1
      fi
    fi
    index=$((index - 1))
  done

  if [ "$failed" = "0" ]; then
    TX_ROLLBACK_OK=1
    echo "✅ 已恢复写入前的 Host 配置。" >&2
    return 0
  fi
  return 1
}

cleanup() {
  local rc="$?"
  local tmp index parent fd device inode stage backup cleanup_ok

  trap - EXIT
  if [ "$TX_STARTED" = "1" ] && [ "$TX_COMPLETE" = "0" ]; then
    rollback_transaction || rc=1
  fi

  for tmp in "${TMP_FILES[@]-}"; do
    [ -n "$tmp" ] || continue
    rm -f "$tmp" || true
  done

  cleanup_ok=0
  if [ "$TX_COMPLETE" = "0" ] \
    && { [ "$TX_STARTED" = "0" ] || [ "$TX_ROLLBACK_OK" = "1" ]; }; then
    cleanup_ok=1
  fi

  index=0
  while [ "$index" -lt "$TX_COUNT" ]; do
    parent="${TX_PARENTS[$index]}"
    fd="${TX_PARENT_FDS[$index]}"
    device="${TX_PARENT_DEVICES[$index]}"
    inode="${TX_PARENT_INODES[$index]}"
    stage="${TX_STAGES[$index]}"
    backup="${TX_BACKUPS[$index]}"
    if [ "$TX_COMPLETE" = "0" ] && [ "$cleanup_ok" = "1" ]; then
      if ! atomic_at "$fd" "$device" "$inode" "$parent" unlink-at \
        --name "$stage" \
        --entry-device "${TX_STAGE_DEVICES[$index]}" \
        --entry-inode "${TX_STAGE_INODES[$index]}" \
        --entry-size "${TX_STAGE_SIZES[$index]}" \
        --entry-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}" \
        --ignore-missing; then
        echo "⚠️  无法清理本轮暂存配置：$parent/$stage" >&2
        rc=1
      fi
      if [ -n "$backup" ] && ! atomic_at \
        "$fd" "$device" "$inode" "$parent" unlink-at \
          --name "$backup" \
          --entry-device "${TX_BACKUP_DEVICES[$index]}" \
          --entry-inode "${TX_BACKUP_INODES[$index]}" \
          --entry-size "${TX_BACKUP_SIZES[$index]}" \
          --entry-mtime-ns "${TX_BACKUP_MTIMES_NS[$index]}" \
          --ignore-missing; then
        echo "⚠️  无法清理本轮备份：$parent/$backup" >&2
        rc=1
      fi
    elif [ "$TX_COMPLETE" = "0" ] && [ "$TX_ROLLBACK_OK" = "0" ]; then
      echo "⚠️  回滚未收口，保留本轮暂存配置：$parent/$stage" >&2
    fi
    index=$((index + 1))
  done
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

render_merged_config() {
  local template_path="$1"
  local dest_path="$2"
  local output_path="$3"
  local current_path="${4:-$dest_path}"
  local current_exists="${5:-auto}"

  PMAI_HOOK_TEMPLATE="$template_path" \
  PMAI_HOOK_DEST="$dest_path" \
  PMAI_HOOK_CURRENT="$current_path" \
  PMAI_HOOK_CURRENT_EXISTS="$current_exists" \
  PMAI_HOOK_RESOLVED_HOME="$PMAI_HOME" \
  python3 - <<'PY' > "$output_path"
import copy
import json
import os
import shlex
import sys
from pathlib import Path

template_path = Path(os.environ["PMAI_HOOK_TEMPLATE"])
dest_path = Path(os.environ["PMAI_HOOK_DEST"])
current_path = Path(os.environ["PMAI_HOOK_CURRENT"])
current_exists = os.environ["PMAI_HOOK_CURRENT_EXISTS"]
resolved_pmai_home = str(Path(os.environ["PMAI_HOOK_RESOLVED_HOME"]).resolve())

try:
    template = json.loads(template_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"invalid template {template_path}: {exc}", file=sys.stderr)
    sys.exit(2)

if current_exists == "auto":
    current_exists = "1" if current_path.exists() else "0"

if current_exists == "1":
    try:
        current = json.loads(current_path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"invalid existing {dest_path}: {exc}", file=sys.stderr)
        sys.exit(2)
else:
    current = {}

if not isinstance(current, dict):
    print(f"invalid existing {dest_path}: root must be an object", file=sys.stderr)
    sys.exit(2)
if "hooks" in current and not isinstance(current["hooks"], dict):
    print(f"invalid existing {dest_path}: hooks must be an object", file=sys.stderr)
    sys.exit(2)
if "hooks" not in current:
    current["hooks"] = {}

managed_invocations = set()
managed_roots = (
    "$HOME/.pmai",
    "${PMAI_HOME:-$HOME/.pmai}",
    "$PMAI_HOME",
    "~/.pmai",
    str(Path.home() / ".pmai"),
    resolved_pmai_home,
)
for root in managed_roots:
    managed_invocations.add(("bash", f"{root}/scripts/check-branch.sh"))
    managed_invocations.add(("node", f"{root}/hooks/review-skill-guard.cjs"))
    managed_invocations.add(("node", f"{root}/hooks/active-build-guard.cjs"))
    managed_invocations.add(("node", f"{root}/hooks/decision-gate-guard.cjs"))
    managed_invocations.add(("node", f"{root}/hooks/finalize-route-guard.cjs"))
    managed_invocations.add(("node", f"{root}/hooks/ui-impact-guard.cjs"))

# Migrate the former project-local hook form used before I-mini. Only these
# exact invocations are owned; a user command that merely contains the same
# basename must remain untouched.
managed_invocations.update({
    ("node", "$CLAUDE_PROJECT_DIR/hooks/review-skill-guard.cjs"),
    ("node", "$CLAUDE_PROJECT_DIR/hooks/active-build-guard.cjs"),
    ("node", "$CLAUDE_PROJECT_DIR/hooks/decision-gate-guard.cjs"),
    ("node", "$CLAUDE_PROJECT_DIR/hooks/finalize-route-guard.cjs"),
    ("node", "$CLAUDE_PROJECT_DIR/hooks/ui-impact-guard.cjs"),
})

def is_pmai_managed_hook(hook):
    if not isinstance(hook, dict):
        return False
    command = hook.get("command")
    if not isinstance(command, str):
        return False
    try:
        argv = shlex.split(command)
    except ValueError:
        return False
    if len(argv) != 2:
        return False
    executable = Path(argv[0]).name
    return (executable, argv[1]) in managed_invocations

def without_managed_hooks(groups):
    retained = []
    for group in groups:
        if not isinstance(group, dict):
            retained.append(group)
            continue
        hooks = group.get("hooks")
        if not isinstance(hooks, list):
            retained.append(group)
            continue
        kept_hooks = [hook for hook in hooks if not is_pmai_managed_hook(hook)]
        if kept_hooks:
            kept_group = copy.deepcopy(group)
            kept_group["hooks"] = kept_hooks
            retained.append(kept_group)
    return retained

template_hooks = template.get("hooks")
if not isinstance(template_hooks, dict):
    print("template missing hooks object", file=sys.stderr)
    sys.exit(2)

current_hooks = current["hooks"]
for event_name, current_groups in current_hooks.items():
    if not isinstance(current_groups, list):
        print(
            f"invalid existing {dest_path}: hooks.{event_name} must be an array",
            file=sys.stderr,
        )
        sys.exit(2)

for event_name, template_groups in template_hooks.items():
    if not isinstance(template_groups, list):
        print(f"invalid template {template_path}: hooks.{event_name} must be an array", file=sys.stderr)
        sys.exit(2)
    current_hooks[event_name] = (
        without_managed_hooks(current_hooks.get(event_name, []))
        + copy.deepcopy(template_groups)
    )

json.dump(current, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY
}

DRIFT=0
PREPARED_LABELS=()
PREPARED_DESTS=()
PREPARED_WRITE_PATHS=()
PREPARED_PARENTS=()
PREPARED_DEST_NAMES=()
PREPARED_PARENT_FDS=()
PREPARED_PARENT_DEVICES=()
PREPARED_PARENT_INODES=()
PREPARED_CURRENTS=()
PREPARED_EXISTED=()
PREPARED_MODES=()
PREPARED_CONFIGS=()
PREPARED_COUNT=0

prepare_host() {
  local label="$1"
  local template_path="$2"
  local dest_path="$3"
  local parent_fd="$4"
  local tmp current_snapshot write_path parent dest_name
  local identity device inode snapshot_meta current_exists mode rc

  if [ ! -f "$template_path" ]; then
    echo "❌ 找不到 ${label} hook 模板：$template_path" >&2
    return 2
  fi

  if [ -L "$dest_path" ]; then
    if [ ! -f "$dest_path" ]; then
      echo "❌ ${label} 配置符号链接未指向普通文件：$dest_path" >&2
      return 2
    fi
  elif [ -e "$dest_path" ]; then
    if [ ! -f "$dest_path" ]; then
      echo "❌ ${label} 配置不是普通文件：$dest_path" >&2
      return 2
    fi
  fi
  write_path="$(canonical_repo_destination "$dest_path")" || {
    echo "❌ ${label} 配置解析到仓库外，拒绝读取或写入：$dest_path" >&2
    return 2
  }
  parent="$(dirname "$write_path")"
  dest_name="$(basename "$write_path")"

  if [ "$MODE" = "install" ]; then
    python3 "$ATOMIC_FILE" ensure-directory \
      --root "$REPO_ROOT" \
      --directory "$parent" || return $?
  elif [ ! -d "$parent" ]; then
    echo "⚠️  ${label} hooks 缺失或已漂移：$dest_path" >&2
    DRIFT=1
    return 0
  fi

  if ! open_parent_fd "$parent_fd" "$parent"; then
    echo "❌ 无法打开 ${label} 配置目录：$parent" >&2
    return 2
  fi
  if identity="$(python3 "$ATOMIC_FILE" bind-directory \
    --directory "$parent" --directory-fd "$parent_fd")"; then
    IFS="$(printf '\t')" read -r device inode <<< "$identity"
  else
    rc=$?
    echo "❌ ${label} 配置目录在绑定期间被改向，拒绝读取或写入：$parent" >&2
    if [ "$MODE" = "check" ]; then
      DRIFT=1
      return 0
    fi
    return "$rc"
  fi

  if ! atomic_at "$parent_fd" "$device" "$inode" "$parent" check-recovery-at \
    --destination-name "$dest_name"; then
    echo "❌ ${label} hooks 存在未收口的原子写入，请先按上方路径恢复。" >&2
    if [ "$MODE" = "check" ]; then
      DRIFT=1
      return 0
    fi
    return 2
  fi

  current_snapshot="$(mktemp)"
  TMP_FILES+=("$current_snapshot")
  if snapshot_meta="$(atomic_at \
    "$parent_fd" "$device" "$inode" "$parent" snapshot-at \
      --destination-name "$dest_name" \
      --output "$current_snapshot")"; then
    IFS="$(printf '\t')" read -r current_exists mode <<< "$snapshot_meta"
  else
    rc=$?
    echo "❌ 无法安全读取 ${label} 配置：$dest_path" >&2
    if [ "$MODE" = "check" ]; then
      DRIFT=1
      return 0
    fi
    return "$rc"
  fi

  tmp="$(mktemp)"
  TMP_FILES+=("$tmp")
  render_merged_config "$template_path" "$dest_path" "$tmp" \
    "$current_snapshot" "$current_exists" || return $?

  PREPARED_LABELS+=("$label")
  PREPARED_DESTS+=("$dest_path")
  PREPARED_WRITE_PATHS+=("$write_path")
  PREPARED_PARENTS+=("$parent")
  PREPARED_DEST_NAMES+=("$dest_name")
  PREPARED_PARENT_FDS+=("$parent_fd")
  PREPARED_PARENT_DEVICES+=("$device")
  PREPARED_PARENT_INODES+=("$inode")
  PREPARED_CURRENTS+=("$current_snapshot")
  PREPARED_EXISTED+=("$current_exists")
  PREPARED_MODES+=("$mode")
  PREPARED_CONFIGS+=("$tmp")
  PREPARED_COUNT=$((PREPARED_COUNT + 1))
}

check_prepared_host() {
  local index="$1"
  local label="${PREPARED_LABELS[$index]}"
  local dest_path="${PREPARED_DESTS[$index]}"
  local tmp="${PREPARED_CONFIGS[$index]}"
  local current="${PREPARED_CURRENTS[$index]}"
  local parent="${PREPARED_PARENTS[$index]}"
  local dest_name="${PREPARED_DEST_NAMES[$index]}"
  local fd="${PREPARED_PARENT_FDS[$index]}"
  local device="${PREPARED_PARENT_DEVICES[$index]}"
  local inode="${PREPARED_PARENT_INODES[$index]}"

  if ! atomic_at "$fd" "$device" "$inode" "$parent" check-recovery-at \
    --destination-name "$dest_name"; then
    echo "❌ ${label} hooks 存在未收口的原子写入，请先按上方路径恢复。" >&2
    DRIFT=1
    return 0
  fi

  if ! display_destination_is_bound \
    "$dest_path" "${PREPARED_WRITE_PATHS[$index]}"; then
    echo "❌ ${label} 配置路径在检查期间被改向或越过仓库边界：$dest_path" >&2
    DRIFT=1
    return 0
  fi

  if [ "${PREPARED_EXISTED[$index]}" = "1" ] \
    && cmp -s "$tmp" "$current"; then
    echo "✅ ${label} hooks 已是最新版：$dest_path"
    return 0
  fi

  echo "⚠️  ${label} hooks 缺失或已漂移：$dest_path" >&2
  DRIFT=1
}

stage_prepared_host() {
  local index="$1"
  local label="${PREPARED_LABELS[$index]}"
  local dest_path="${PREPARED_DESTS[$index]}"
  local rendered="${PREPARED_CONFIGS[$index]}"
  local write_path="${PREPARED_WRITE_PATHS[$index]}"
  local parent="${PREPARED_PARENTS[$index]}"
  local dest_name="${PREPARED_DEST_NAMES[$index]}"
  local fd="${PREPARED_PARENT_FDS[$index]}"
  local device="${PREPARED_PARENT_DEVICES[$index]}"
  local inode="${PREPARED_PARENT_INODES[$index]}"
  local current="${PREPARED_CURRENTS[$index]}"
  local existed="${PREPARED_EXISTED[$index]}"
  local mode="${PREPARED_MODES[$index]}"
  local prepared prepared_fields_end extra
  local original_device original_inode original_size original_mtime_ns
  local backup backup_device backup_inode backup_size backup_mtime_ns
  local stage stage_device stage_inode stage_size stage_mtime_ns rc field

  atomic_at "$fd" "$device" "$inode" "$parent" check-recovery-at \
    --destination-name "$dest_name" || {
    echo "❌ ${label} hooks 存在未收口的原子写入，请先按上方路径恢复。" >&2
    return 2
  }

  if ! display_destination_is_bound "$dest_path" "$write_path"; then
    echo "❌ ${label} 配置路径在准备期间被改向或越过仓库边界：$dest_path" >&2
    return 2
  fi

  if [ "$existed" = "1" ] && cmp -s "$rendered" "$current"; then
    echo "✅ ${label} hooks 已是最新版：$dest_path"
    return 0
  fi

  if [ "$existed" = "1" ]; then
    prepared="$(atomic_at "$fd" "$device" "$inode" "$parent" prepare-at \
      --destination-name "$dest_name" \
      --rendered "$rendered" \
      --expected "$current" \
      --expected-mode "$mode")" || return $?
  else
    prepared="$(atomic_at "$fd" "$device" "$inode" "$parent" prepare-at \
      --destination-name "$dest_name" \
      --rendered "$rendered" \
      --expected-mode "$mode")" || return $?
  fi
  prepared_fields_end="__PMAI_PREPARED_FIELDS_END__"
  prepared="$prepared$(printf '\t')$prepared_fields_end"
  IFS="$(printf '\t')" read -r \
    original_device original_inode original_size original_mtime_ns \
    backup backup_device backup_inode backup_size backup_mtime_ns \
    stage stage_device stage_inode stage_size stage_mtime_ns extra <<< "$prepared"
  if [ "$extra" != "$prepared_fields_end" ]; then
    echo "❌ ${label} 原子事务返回的身份字段数不是 14，已停止：$dest_path" >&2
    return 2
  fi
  for field in \
    "$original_device" "$original_inode" "$original_size" "$original_mtime_ns" \
    "$backup" "$backup_device" "$backup_inode" "$backup_size" "$backup_mtime_ns" \
    "$stage" "$stage_device" "$stage_inode" "$stage_size" "$stage_mtime_ns"; do
    if [ -z "$field" ]; then
      echo "❌ ${label} 原子事务返回了空身份字段，已停止：$dest_path" >&2
      return 2
    fi
  done
  if ! is_decimal_identity "$stage_device" \
    || ! is_decimal_identity "$stage_inode" \
    || ! is_decimal_identity "$stage_size" \
    || ! is_decimal_identity "$stage_mtime_ns"; then
    echo "❌ ${label} 原子事务返回了非法 stage 身份，已停止：$dest_path" >&2
    return 2
  fi
  if [ "$existed" = "1" ]; then
    if [ "$original_device" = "-" ] || [ "$original_inode" = "-" ] \
      || [ "$original_size" = "-" ] || [ "$original_mtime_ns" = "-" ] \
      || [ "$backup" = "-" ] || [ "$backup_device" = "-" ] \
      || [ "$backup_inode" = "-" ] || [ "$backup_size" = "-" ] \
      || [ "$backup_mtime_ns" = "-" ] \
      || ! is_decimal_identity "$original_device" \
      || ! is_decimal_identity "$original_inode" \
      || ! is_decimal_identity "$original_size" \
      || ! is_decimal_identity "$original_mtime_ns" \
      || ! is_decimal_identity "$backup_device" \
      || ! is_decimal_identity "$backup_inode" \
      || ! is_decimal_identity "$backup_size" \
      || ! is_decimal_identity "$backup_mtime_ns"; then
      echo "❌ ${label} 原子事务返回了非法 replacement 身份组合，已停止：$dest_path" >&2
      return 2
    fi
  elif [ "$existed" = "0" ]; then
    if [ "$original_device" != "-" ] || [ "$original_inode" != "-" ] \
      || [ "$original_size" != "-" ] || [ "$original_mtime_ns" != "-" ] \
      || [ "$backup" != "-" ] || [ "$backup_device" != "-" ] \
      || [ "$backup_inode" != "-" ] || [ "$backup_size" != "-" ] \
      || [ "$backup_mtime_ns" != "-" ]; then
      echo "❌ ${label} 原子事务返回了非法 creation 占位符组合，已停止：$dest_path" >&2
      return 2
    fi
    original_device=""
    original_inode=""
    original_size=""
    original_mtime_ns=""
    backup=""
    backup_device=""
    backup_inode=""
    backup_size=""
    backup_mtime_ns=""
  else
    echo "❌ ${label} 原子事务缺少有效的原配置状态，已停止：$dest_path" >&2
    return 2
  fi

  TX_LABELS+=("$label")
  TX_DESTS+=("$write_path")
  TX_DISPLAY_DESTS+=("$dest_path")
  TX_PARENTS+=("$parent")
  TX_DEST_NAMES+=("$dest_name")
  TX_PARENT_FDS+=("$fd")
  TX_PARENT_DEVICES+=("$device")
  TX_PARENT_INODES+=("$inode")
  TX_STAGES+=("$stage")
  TX_STAGE_DEVICES+=("$stage_device")
  TX_STAGE_INODES+=("$stage_inode")
  TX_STAGE_SIZES+=("$stage_size")
  TX_STAGE_MTIMES_NS+=("$stage_mtime_ns")
  TX_EXISTED+=("$existed")
  TX_MODES+=("$mode")
  TX_BACKUPS+=("$backup")
  TX_BACKUP_DEVICES+=("$backup_device")
  TX_BACKUP_INODES+=("$backup_inode")
  TX_BACKUP_SIZES+=("$backup_size")
  TX_BACKUP_MTIMES_NS+=("$backup_mtime_ns")
  TX_ORIGINAL_DEVICES+=("$original_device")
  TX_ORIGINAL_INODES+=("$original_inode")
  TX_ORIGINAL_SIZES+=("$original_size")
  TX_ORIGINAL_MTIMES_NS+=("$original_mtime_ns")
  TX_RENDERED+=("$rendered")
  TX_COUNT=$((TX_COUNT + 1))
}

verify_transaction_input() {
  local index="$1"
  local dest="${TX_DESTS[$index]}"
  local display_dest="${TX_DISPLAY_DESTS[$index]}"
  local parent="${TX_PARENTS[$index]}"
  local dest_name="${TX_DEST_NAMES[$index]}"
  local fd="${TX_PARENT_FDS[$index]}"
  local device="${TX_PARENT_DEVICES[$index]}"
  local inode="${TX_PARENT_INODES[$index]}"
  local backup state

  if ! display_destination_is_bound "$display_dest" "$dest"; then
    echo "❌ Host 配置路径在刷新期间被改向或越过仓库边界，已停止：$display_dest" >&2
    return 2
  fi
  if [ "${TX_EXISTED[$index]}" = "1" ]; then
    backup="${TX_BACKUPS[$index]}"
    state="$(atomic_at "$fd" "$device" "$inode" "$parent" inspect-at \
      --destination-name "$dest_name" \
      --destination-device "${TX_ORIGINAL_DEVICES[$index]}" \
      --destination-inode "${TX_ORIGINAL_INODES[$index]}" \
      --destination-size "${TX_ORIGINAL_SIZES[$index]}" \
      --destination-mtime-ns "${TX_ORIGINAL_MTIMES_NS[$index]}" \
      --expected-name "$backup" \
      --expected-entry-device "${TX_BACKUP_DEVICES[$index]}" \
      --expected-entry-inode "${TX_BACKUP_INODES[$index]}" \
      --expected-entry-size "${TX_BACKUP_SIZES[$index]}" \
      --expected-entry-mtime-ns "${TX_BACKUP_MTIMES_NS[$index]}" \
      --expected-mode "${TX_MODES[$index]}" 2>/dev/null || true)"
    if [ "$state" != "same" ]; then
      echo "❌ Host 配置在刷新期间被其它进程修改，已停止：$display_dest" >&2
      return 2
    fi
  else
    state="$(atomic_at "$fd" "$device" "$inode" "$parent" inspect-at \
      --destination-name "$dest_name" \
      --expected-path "${TX_RENDERED[$index]}" \
      --expected-mode "${TX_MODES[$index]}" 2>/dev/null || true)"
    if [ "$state" != "missing" ]; then
      echo "❌ Host 配置在刷新期间被其它进程创建，已停止且未覆盖：$display_dest" >&2
      return 2
    fi
  fi
}

verify_committed_output() {
  local index="$1"
  local dest="${TX_DESTS[$index]}"
  local display_dest="${TX_DISPLAY_DESTS[$index]}"
  local rendered="${TX_RENDERED[$index]}"
  local parent="${TX_PARENTS[$index]}"
  local dest_name="${TX_DEST_NAMES[$index]}"
  local fd="${TX_PARENT_FDS[$index]}"
  local device="${TX_PARENT_DEVICES[$index]}"
  local inode="${TX_PARENT_INODES[$index]}"
  local state

  if ! display_destination_is_bound "$display_dest" "$dest"; then
    echo "❌ Host 配置路径在写入期间被改向或越过仓库边界，正在回滚：$display_dest" >&2
    return 2
  fi

  state="$(atomic_at "$fd" "$device" "$inode" "$parent" inspect-at \
    --destination-name "$dest_name" \
    --destination-device "${TX_STAGE_DEVICES[$index]}" \
    --destination-inode "${TX_STAGE_INODES[$index]}" \
    --destination-size "${TX_STAGE_SIZES[$index]}" \
    --destination-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}" \
    --expected-path "$rendered" \
    --expected-mode "${TX_MODES[$index]}" 2>/dev/null || true)"
  if [ "$state" != "same" ]; then
    echo "❌ Host 配置写入后内容或权限不一致，正在回滚：$display_dest" >&2
    return 2
  fi
}

verify_transaction_inputs() {
  local index

  index=0
  while [ "$index" -lt "$TX_COUNT" ]; do
    verify_transaction_input "$index" || return $?
    index=$((index + 1))
  done
}

commit_transaction() {
  local index display_dest parent dest_name fd device inode stage

  TX_STARTED=1
  index=0
  while [ "$index" -lt "$TX_COUNT" ]; do
    display_dest="${TX_DISPLAY_DESTS[$index]}"
    parent="${TX_PARENTS[$index]}"
    dest_name="${TX_DEST_NAMES[$index]}"
    fd="${TX_PARENT_FDS[$index]}"
    device="${TX_PARENT_DEVICES[$index]}"
    inode="${TX_PARENT_INODES[$index]}"
    stage="${TX_STAGES[$index]}"
    # Recheck immediately before every rename. The earlier all-host check keeps
    # the transaction fail-fast; this closes the window opened by prior hosts.
    verify_transaction_input "$index" || return $?
    # Mark the destination before rename so a signal delivered immediately
    # after a successful rename still includes this host in rollback.
    TX_COMMITTED_COUNT=$((index + 1))
    if [ "${TX_EXISTED[$index]}" = "1" ]; then
      if ! atomic_at "$fd" "$device" "$inode" "$parent" replace-at \
        --destination-name "$dest_name" \
        --destination-device "${TX_ORIGINAL_DEVICES[$index]}" \
        --destination-inode "${TX_ORIGINAL_INODES[$index]}" \
        --destination-size "${TX_ORIGINAL_SIZES[$index]}" \
        --destination-mtime-ns "${TX_ORIGINAL_MTIMES_NS[$index]}" \
        --staged-name "$stage" \
        --staged-device "${TX_STAGE_DEVICES[$index]}" \
        --staged-inode "${TX_STAGE_INODES[$index]}" \
        --staged-size "${TX_STAGE_SIZES[$index]}" \
        --staged-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}" \
        --expected-name "${TX_BACKUPS[$index]}" \
        --expected-entry-device "${TX_BACKUP_DEVICES[$index]}" \
        --expected-entry-inode "${TX_BACKUP_INODES[$index]}" \
        --expected-entry-size "${TX_BACKUP_SIZES[$index]}" \
        --expected-entry-mtime-ns "${TX_BACKUP_MTIMES_NS[$index]}" \
        --expected-mode "${TX_MODES[$index]}"; then
        echo "❌ 写入 Host 配置失败：$display_dest" >&2
        return 1
      fi
    elif ! atomic_at "$fd" "$device" "$inode" "$parent" create-at \
      --destination-name "$dest_name" \
      --staged-name "$stage" \
      --staged-device "${TX_STAGE_DEVICES[$index]}" \
      --staged-inode "${TX_STAGE_INODES[$index]}" \
      --staged-size "${TX_STAGE_SIZES[$index]}" \
      --staged-mtime-ns "${TX_STAGE_MTIMES_NS[$index]}"; then
      echo "❌ 写入 Host 配置失败：$display_dest" >&2
      return 1
    fi
    verify_committed_output "$index" || return $?
    index=$((index + 1))
  done
  index=0
  while [ "$index" -lt "$TX_COUNT" ]; do
    verify_committed_output "$index" || return $?
    index=$((index + 1))
  done
  TX_COMPLETE=1
}

# Render and stage every selected host before the transaction replaces either
# destination. The EXIT trap restores already-attempted hosts on any failure.
if [ "$HOST" = "all" ] || [ "$HOST" = "claude" ]; then
  prepare_host "Claude Code" "$PMAI_HOME/templates/settings.json.tmpl" \
    "$REPO_ROOT/.claude/settings.json" 7
fi
if [ "$HOST" = "all" ] || [ "$HOST" = "codex" ]; then
  prepare_host "Codex" "$PMAI_HOME/templates/codex-hooks.json.tmpl" \
    "$REPO_ROOT/.codex/hooks.json" 8
fi

if [ "$MODE" = "check" ]; then
  index=0
  while [ "$index" -lt "$PREPARED_COUNT" ]; do
    check_prepared_host "$index"
    index=$((index + 1))
  done
  if [ "$DRIFT" = "1" ]; then
    echo "   刷新：bash \"$PMAI_HOME/scripts/install-project-hooks.sh\"" >&2
    exit 1
  fi
  exit 0
fi

index=0
while [ "$index" -lt "$PREPARED_COUNT" ]; do
  stage_prepared_host "$index"
  index=$((index + 1))
done

if [ "$TX_COUNT" -gt 0 ]; then
  verify_transaction_inputs
  commit_transaction
fi

index=0
while [ "$index" -lt "$TX_COUNT" ]; do
  if [ -n "${TX_BACKUPS[$index]}" ]; then
    echo "📦 已备份原 ${TX_LABELS[$index]} 配置到：${TX_PARENTS[$index]}/${TX_BACKUPS[$index]}"
  fi
  echo "✅ ${TX_LABELS[$index]} hooks 已安装：${TX_DISPLAY_DESTS[$index]}"
  index=$((index + 1))
done
echo "   PMAI 只更新自有 hook；其它宿主配置和自定义 hook 保持不变。"
