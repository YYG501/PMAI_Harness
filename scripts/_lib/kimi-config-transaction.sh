#!/usr/bin/env bash
# Isolate cross-version Kimi config writers behind a recoverable working copy.

PMAI_KIMI_TX_ATOMIC_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/atomic_file.py"
PMAI_KIMI_TX_CONFIG=""
PMAI_KIMI_TX_BACKUP_PREFIX=""
PMAI_KIMI_TX_BACKUP_DIR=""
PMAI_KIMI_TX_ENTRY_BACKUP=""
PMAI_KIMI_TX_REFERENT=""
PMAI_KIMI_TX_REFERENT_BACKUP=""
PMAI_KIMI_TX_LINK_TARGET=""
PMAI_KIMI_TX_ORIGINAL_KIND=""
PMAI_KIMI_TX_QUARANTINE=""
PMAI_KIMI_TX_STAGE=""
PMAI_KIMI_TX_STAGE_PATHS=()
PMAI_KIMI_TX_ENTRY_CLAIMED=0
PMAI_KIMI_TX_SNAPSHOT_READY=0
PMAI_KIMI_TX_REFERENT_MAY_BE_UPDATED=0

pmai_kimi_config_tx_reset() {
  PMAI_KIMI_TX_CONFIG=""
  PMAI_KIMI_TX_BACKUP_PREFIX=""
  PMAI_KIMI_TX_BACKUP_DIR=""
  PMAI_KIMI_TX_ENTRY_BACKUP=""
  PMAI_KIMI_TX_REFERENT=""
  PMAI_KIMI_TX_REFERENT_BACKUP=""
  PMAI_KIMI_TX_LINK_TARGET=""
  PMAI_KIMI_TX_ORIGINAL_KIND=""
  PMAI_KIMI_TX_QUARANTINE=""
  PMAI_KIMI_TX_STAGE=""
  PMAI_KIMI_TX_STAGE_PATHS=()
  PMAI_KIMI_TX_ENTRY_CLAIMED=0
  PMAI_KIMI_TX_SNAPSHOT_READY=0
  PMAI_KIMI_TX_REFERENT_MAY_BE_UPDATED=0
}

pmai_kimi_config_tx_ensure_backup_dir() {
  local parent template

  [ -n "$PMAI_KIMI_TX_BACKUP_DIR" ] && return 0
  parent=$(dirname "$PMAI_KIMI_TX_CONFIG")
  if [ ! -d "$parent" ]; then
    echo "❌ Kimi config 父目录不存在：$parent" >&2
    return 1
  fi
  template="$parent/${PMAI_KIMI_TX_BACKUP_PREFIX}.$$.XXXXXXXX"
  if ! PMAI_KIMI_TX_BACKUP_DIR=$(mktemp -d "$template"); then
    PMAI_KIMI_TX_BACKUP_DIR=""
    echo "❌ 无法创建 Kimi config 恢复目录：$template" >&2
    return 1
  fi
  PMAI_KIMI_TX_ENTRY_BACKUP="$PMAI_KIMI_TX_BACKUP_DIR/original-entry"
  PMAI_KIMI_TX_REFERENT_BACKUP="$PMAI_KIMI_TX_BACKUP_DIR/original-referent"
  return 0
}

pmai_kimi_config_tx_snapshot() {
  local config="$1"
  local backup_prefix="$2"

  pmai_kimi_config_tx_reset
  case "$backup_prefix" in
    ""|*/*)
      echo "❌ Kimi config 备份前缀无效：$backup_prefix" >&2
      return 1
      ;;
  esac
  PMAI_KIMI_TX_CONFIG="$config"
  PMAI_KIMI_TX_BACKUP_PREFIX="$backup_prefix"

  if [ ! -e "$config" ] && [ ! -L "$config" ]; then
    PMAI_KIMI_TX_ORIGINAL_KIND="missing"
    PMAI_KIMI_TX_SNAPSHOT_READY=1
    return 0
  fi

  pmai_kimi_config_tx_ensure_backup_dir || return 1
  # Claim the directory entry first. All classification below reads the hidden
  # recovery entry, so a concurrent path swap cannot mix one symlink identity
  # with another referent.
  PMAI_KIMI_TX_ORIGINAL_KIND="claimed"
  PMAI_KIMI_TX_ENTRY_CLAIMED=1
  mv -- "$config" "$PMAI_KIMI_TX_ENTRY_BACKUP" || return 1

  if [ -L "$PMAI_KIMI_TX_ENTRY_BACKUP" ]; then
    PMAI_KIMI_TX_LINK_TARGET=$(readlink "$PMAI_KIMI_TX_ENTRY_BACKUP") || return 1
    if ! PMAI_KIMI_TX_REFERENT=$(python3 -c \
      'import os, sys
config = os.path.abspath(sys.argv[1])
target = sys.argv[2]
if not os.path.isabs(target):
    target = os.path.join(os.path.dirname(config), target)
print(os.path.realpath(target))' "$config" "$PMAI_KIMI_TX_LINK_TARGET"); then
      echo "❌ 无法解析 Kimi config symlink：$config" >&2
      return 1
    fi
    if [ -e "$PMAI_KIMI_TX_REFERENT" ] || [ -L "$PMAI_KIMI_TX_REFERENT" ]; then
      if [ ! -f "$PMAI_KIMI_TX_REFERENT" ] || [ -L "$PMAI_KIMI_TX_REFERENT" ]; then
        echo "❌ Kimi config symlink 目标不是普通文件：$PMAI_KIMI_TX_REFERENT" >&2
        return 1
      fi
      cp -p "$PMAI_KIMI_TX_REFERENT" "$PMAI_KIMI_TX_REFERENT_BACKUP" || return 1
      PMAI_KIMI_TX_ORIGINAL_KIND="symlink-live"
    else
      PMAI_KIMI_TX_ORIGINAL_KIND="symlink-dangling"
    fi
  elif [ -f "$PMAI_KIMI_TX_ENTRY_BACKUP" ]; then
    PMAI_KIMI_TX_ORIGINAL_KIND="file"
  else
    echo "❌ Kimi config 不是普通文件或 symlink：$config" >&2
    return 1
  fi

  case "$PMAI_KIMI_TX_ORIGINAL_KIND" in
    file)
      cp -p "$PMAI_KIMI_TX_ENTRY_BACKUP" "$config" || return 1
      ;;
    symlink-live)
      cp -p "$PMAI_KIMI_TX_REFERENT_BACKUP" "$config" || return 1
      ;;
  esac
  PMAI_KIMI_TX_SNAPSHOT_READY=1
  return 0
}

pmai_kimi_config_tx_needs_check() {
  case "$PMAI_KIMI_TX_ORIGINAL_KIND" in
    file|symlink-live) return 0 ;;
    *) return 1 ;;
  esac
}

pmai_kimi_config_tx_quarantine_current() {
  local candidate

  if [ ! -e "$PMAI_KIMI_TX_CONFIG" ] && [ ! -L "$PMAI_KIMI_TX_CONFIG" ]; then
    PMAI_KIMI_TX_QUARANTINE=""
    return 0
  fi
  pmai_kimi_config_tx_ensure_backup_dir || return 1
  while :; do
    candidate="$PMAI_KIMI_TX_BACKUP_DIR/current.$$.$RANDOM"
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      break
    fi
  done
  if ! mv -- "$PMAI_KIMI_TX_CONFIG" "$candidate"; then
    echo "⚠️  无法隔离当前 Kimi config：$PMAI_KIMI_TX_CONFIG" >&2
    return 1
  fi
  PMAI_KIMI_TX_QUARANTINE="$candidate"
}

pmai_kimi_config_tx_restore_entry() {
  local restore_failed=0

  case "$PMAI_KIMI_TX_ORIGINAL_KIND" in
    missing)
      pmai_kimi_config_tx_quarantine_current || return 1
      return 0
      ;;
    symlink-live|symlink-dangling)
      if [ ! -e "$PMAI_KIMI_TX_ENTRY_BACKUP" ] \
        && [ ! -L "$PMAI_KIMI_TX_ENTRY_BACKUP" ]; then
        if [ -L "$PMAI_KIMI_TX_CONFIG" ] \
          && [ "$(readlink "$PMAI_KIMI_TX_CONFIG")" = "$PMAI_KIMI_TX_LINK_TARGET" ]; then
          return 0
        fi
        echo "⚠️  Kimi config symlink 备份缺失，当前路径保持不动：$PMAI_KIMI_TX_CONFIG" >&2
        return 1
      fi
      ;;
    claimed)
      if [ ! -e "$PMAI_KIMI_TX_ENTRY_BACKUP" ] \
        && [ ! -L "$PMAI_KIMI_TX_ENTRY_BACKUP" ]; then
        if [ -e "$PMAI_KIMI_TX_CONFIG" ] || [ -L "$PMAI_KIMI_TX_CONFIG" ]; then
          return 0
        fi
        echo "⚠️  Kimi config claim 失败且原路径已不存在：$PMAI_KIMI_TX_CONFIG" >&2
        return 1
      fi
      ;;
    file)
      if [ ! -f "$PMAI_KIMI_TX_ENTRY_BACKUP" ] \
        || [ -L "$PMAI_KIMI_TX_ENTRY_BACKUP" ]; then
        if [ "$PMAI_KIMI_TX_SNAPSHOT_READY" = "0" ] \
          && [ -f "$PMAI_KIMI_TX_CONFIG" ] \
          && [ ! -L "$PMAI_KIMI_TX_CONFIG" ]; then
          return 0
        fi
        echo "⚠️  Kimi config 文件备份缺失，当前路径保持不动：$PMAI_KIMI_TX_CONFIG" >&2
        return 1
      fi
      ;;
    *)
      return 0
      ;;
  esac

  pmai_kimi_config_tx_quarantine_current || return 1
  if ! mv -- "$PMAI_KIMI_TX_ENTRY_BACKUP" "$PMAI_KIMI_TX_CONFIG"; then
    echo "⚠️  无法恢复 Kimi config，备份保留在：$PMAI_KIMI_TX_ENTRY_BACKUP" >&2
    restore_failed=1
    if [ -n "$PMAI_KIMI_TX_QUARANTINE" ] \
      && { [ -e "$PMAI_KIMI_TX_QUARANTINE" ] || [ -L "$PMAI_KIMI_TX_QUARANTINE" ]; } \
      && [ ! -e "$PMAI_KIMI_TX_CONFIG" ] && [ ! -L "$PMAI_KIMI_TX_CONFIG" ]; then
      if ! mv -- "$PMAI_KIMI_TX_QUARANTINE" "$PMAI_KIMI_TX_CONFIG" 2>/dev/null; then
        echo "⚠️  Kimi config working copy 也无法放回：$PMAI_KIMI_TX_QUARANTINE" >&2
      fi
    fi
  fi
  return "$restore_failed"
}

pmai_kimi_config_tx_stage_file() {
  local source="$1"
  local destination="$2"
  local parent candidate

  parent=$(dirname "$destination")
  if [ ! -d "$parent" ]; then
    echo "❌ Kimi config symlink 目标目录不存在：$parent" >&2
    return 1
  fi
  while :; do
    candidate="$parent/.pmai-kimi-config-stage.$$.$RANDOM"
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      break
    fi
  done
  PMAI_KIMI_TX_STAGE="$candidate"
  PMAI_KIMI_TX_STAGE_PATHS+=("$candidate")
  if ! cp -p "$source" "$candidate"; then
    if rm -f -- "$candidate" 2>/dev/null; then
      PMAI_KIMI_TX_STAGE=""
    fi
    return 1
  fi
  return 0
}

pmai_kimi_config_tx_replace_staged() {
  local destination="$1"
  local expected="${2:-}"

  if [ -z "$PMAI_KIMI_TX_STAGE" ]; then
    echo "❌ Kimi config 缺少待提交 stage：$destination" >&2
    return 1
  fi
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    if [ ! -f "$destination" ] || [ -L "$destination" ]; then
      echo "❌ Kimi config symlink 目标不再是普通文件：$destination" >&2
      return 1
    fi
  fi
  if [ -n "$expected" ]; then
    if [ ! -f "$PMAI_KIMI_TX_ATOMIC_FILE" ]; then
      echo "❌ Kimi config 缺少原子 CAS helper：$PMAI_KIMI_TX_ATOMIC_FILE" >&2
      return 1
    fi
    python3 "$PMAI_KIMI_TX_ATOMIC_FILE" replace \
      --destination "$destination" \
      --staged "$PMAI_KIMI_TX_STAGE" \
      --expected "$expected" || return 1
  else
    python3 -c 'import os, sys; os.replace(sys.argv[1], sys.argv[2])' \
      "$PMAI_KIMI_TX_STAGE" "$destination" || return 1
  fi
  PMAI_KIMI_TX_STAGE=""
  return 0
}

pmai_kimi_config_tx_files_equal() {
  python3 - "$1" "$2" <<'PY'
import os
import stat
import sys

left, right = sys.argv[1:]
try:
    left_stat = os.stat(left, follow_symlinks=False)
    right_stat = os.stat(right, follow_symlinks=False)
    same = (
        stat.S_ISREG(left_stat.st_mode)
        and stat.S_ISREG(right_stat.st_mode)
        and stat.S_IMODE(left_stat.st_mode) == stat.S_IMODE(right_stat.st_mode)
        and open(left, "rb").read() == open(right, "rb").read()
    )
except OSError:
    same = False
raise SystemExit(0 if same else 1)
PY
}

pmai_kimi_config_tx_finalize() {
  [ "$PMAI_KIMI_TX_SNAPSHOT_READY" = "1" ] || {
    echo "❌ Kimi config 事务快照未完成，拒绝提交。" >&2
    return 1
  }

  case "$PMAI_KIMI_TX_ORIGINAL_KIND" in
    file)
      if [ ! -f "$PMAI_KIMI_TX_CONFIG" ] || [ -L "$PMAI_KIMI_TX_CONFIG" ]; then
        echo "❌ Kimi config working copy 类型漂移：$PMAI_KIMI_TX_CONFIG" >&2
        return 1
      fi
      ;;
    missing)
      pmai_kimi_config_tx_quarantine_current || return 1
      ;;
    symlink-dangling)
      pmai_kimi_config_tx_restore_entry || return 1
      ;;
    symlink-live)
      if [ ! -f "$PMAI_KIMI_TX_CONFIG" ] || [ -L "$PMAI_KIMI_TX_CONFIG" ]; then
        echo "❌ Kimi config working copy 类型漂移：$PMAI_KIMI_TX_CONFIG" >&2
        return 1
      fi
      pmai_kimi_config_tx_stage_file \
        "$PMAI_KIMI_TX_CONFIG" "$PMAI_KIMI_TX_REFERENT" || return 1
      pmai_kimi_config_tx_restore_entry || return 1
      PMAI_KIMI_TX_REFERENT_MAY_BE_UPDATED=1
      pmai_kimi_config_tx_replace_staged \
        "$PMAI_KIMI_TX_REFERENT" "$PMAI_KIMI_TX_REFERENT_BACKUP" || return 1
      if ! cmp -s "$PMAI_KIMI_TX_QUARANTINE" "$PMAI_KIMI_TX_REFERENT"; then
        echo "❌ Kimi config symlink 目标提交后校验失败：$PMAI_KIMI_TX_REFERENT" >&2
        return 1
      fi
      ;;
    *)
      echo "❌ 未知 Kimi config 事务状态：$PMAI_KIMI_TX_ORIGINAL_KIND" >&2
      return 1
      ;;
  esac
}

pmai_kimi_config_tx_restore() {
  local restore_failed=0

  if [ "$PMAI_KIMI_TX_REFERENT_MAY_BE_UPDATED" = "1" ]; then
    if [ -f "$PMAI_KIMI_TX_REFERENT_BACKUP" ] \
      && [ ! -L "$PMAI_KIMI_TX_REFERENT_BACKUP" ]; then
      if ! pmai_kimi_config_tx_files_equal \
        "$PMAI_KIMI_TX_REFERENT_BACKUP" "$PMAI_KIMI_TX_REFERENT"; then
        if pmai_kimi_config_tx_stage_file \
          "$PMAI_KIMI_TX_REFERENT_BACKUP" "$PMAI_KIMI_TX_REFERENT"; then
          pmai_kimi_config_tx_replace_staged \
            "$PMAI_KIMI_TX_REFERENT" "$PMAI_KIMI_TX_QUARANTINE" \
            || restore_failed=1
        else
          restore_failed=1
        fi
      fi
    else
      echo "⚠️  Kimi config referent 备份缺失：$PMAI_KIMI_TX_REFERENT_BACKUP" >&2
      restore_failed=1
    fi
  fi

  if [ "$PMAI_KIMI_TX_ENTRY_CLAIMED" = "1" ] \
    || [ "$PMAI_KIMI_TX_SNAPSHOT_READY" = "1" ]; then
    pmai_kimi_config_tx_restore_entry || restore_failed=1
  fi

  if [ "$restore_failed" = "0" ]; then
    pmai_kimi_config_tx_cleanup "Kimi config 回滚" || restore_failed=1
  elif [ -n "$PMAI_KIMI_TX_BACKUP_DIR" ]; then
    echo "⚠️  Kimi config 回滚未完整，恢复材料保留在：$PMAI_KIMI_TX_BACKUP_DIR" >&2
  fi
  return "$restore_failed"
}

pmai_kimi_config_tx_cleanup() {
  local label="${1:-Kimi config 事务}"
  local cleanup_failed=0
  local stage

  for stage in ${PMAI_KIMI_TX_STAGE_PATHS[@]+"${PMAI_KIMI_TX_STAGE_PATHS[@]}"}; do
    [ -n "$stage" ] || continue
    if { [ -e "$stage" ] || [ -L "$stage" ]; } \
      && ! rm -f -- "$stage"; then
      echo "⚠️  $label临时文件未删除：$stage" >&2
      cleanup_failed=1
    fi
  done
  if [ -n "$PMAI_KIMI_TX_BACKUP_DIR" ] \
    && { [ -e "$PMAI_KIMI_TX_BACKUP_DIR" ] || [ -L "$PMAI_KIMI_TX_BACKUP_DIR" ]; }; then
    if ! rm -rf -- "$PMAI_KIMI_TX_BACKUP_DIR"; then
      echo "⚠️  $label恢复材料未删除，保留在：$PMAI_KIMI_TX_BACKUP_DIR" >&2
      cleanup_failed=1
    fi
  fi
  return "$cleanup_failed"
}
