#!/usr/bin/env bash
# quick-fix.sh — Isolated fast path for PM-approved small changes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_setup-deps.sh"
source "$SCRIPT_DIR/_lib/worktree.sh"

usage() {
  cat >&2 <<'EOF'
用法:
  bash quick-fix.sh [--skip-tsc] [--force] "<desc>"
  bash quick-fix.sh --cancel <tmp-quick-branch>
  bash quick-fix.sh --cleanup
  bash quick-fix.sh --history [N]
  bash quick-fix.sh --snapshot

测试/自动化可用环境变量:
  QUICK_FIX_COMMAND      在 worktree 内执行的命令
  QUICK_FIX_APPROVE=1    自动通过 diff 审批
  QUICK_FIX_DECISION     自动审批决策：pass / redo / cancel
  QUICK_FIX_ASSUME_YES=1 自动确认 cleanup
EOF
  exit 1
}

find_main_repo_root() {
  local common
  common=$(git rev-parse --git-common-dir 2>/dev/null || true)
  if [ -z "$common" ]; then
    echo "错误：当前目录不在 git 仓库中" >&2
    exit 1
  fi
  common=$(cd "$common" && pwd)
  if [[ "$common" == */.git ]]; then
    cd "$common/.." && pwd
  elif [[ "$common" == */.git/worktrees/* ]]; then
    echo "${common%%/.git/worktrees/*}"
  else
    git rev-parse --show-toplevel
  fi
}

realpath_m() {
  local path="$1"
  python3 - "$path" <<'PY'
import os
import sys
print(os.path.realpath(sys.argv[1]))
PY
}

sanitize_desc() {
  local raw="$1"
  local out="${raw//|/｜}"
  out="${out//\`/}"
  out="${out//\$/}"
  out="${out//;/,}"
  out=$(printf "%s" "$out" | tr -d '\n\r')
  echo "${out:0:120}"
}

current_branch() {
  git -C "$1" branch --show-current 2>/dev/null || true
}

# 设全局 BASE_BRANCH + BASE_WORKTREE，决定 quick-fix 改的目标分支与合并工作树。
# 三种合法启动位置：
#   1) 主仓根 + branch=main           → BASE_BRANCH=main、BASE_WORKTREE=repo_root（main mode）
#   2) build-* worktree（任意分支）   → BASE_BRANCH=该 worktree 当前分支、BASE_WORKTREE=该 worktree（build mode）
#   3) task-* worktree                → 拒绝（历史 task worktree，不再作为当前入口）
ensure_quickfix_root() {
  local repo_root="$1"
  local current_root branch
  current_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -z "$current_root" ]; then
    echo "错误：/pmai-quick-fix 必须从 git 仓库内启动。" >&2
    exit 1
  fi
  branch=$(current_branch "$current_root")
  if [ -z "$branch" ]; then
    echo "错误：无法识别当前分支（HEAD detached？）。" >&2
    exit 1
  fi

  if [ "$(realpath_m "$current_root")" = "$(realpath_m "$repo_root")" ]; then
    # 主仓根
    if [ "$branch" != "main" ]; then
      echo "错误：在主仓根但当前分支不是 main：$branch" >&2
      exit 1
    fi
    BASE_BRANCH="main"
    BASE_WORKTREE="$repo_root"
    return 0
  fi

  # 在 worktree 内（current_root != repo_root）
  case "$branch" in
    build-*)
      BASE_BRANCH="$branch"
      BASE_WORKTREE="$current_root"
      ;;
    task-*)
      echo "错误：/pmai-quick-fix 不能在历史 task worktree 内启动。请回 main 或 build-* worktree。" >&2
      exit 1
      ;;
    main)
      echo "错误：在 worktree 内但分支是 main，配置异常。" >&2
      exit 1
      ;;
    *)
      echo "错误：/pmai-quick-fix 只能从 main 分支或 build-* worktree 启动，当前分支：$branch" >&2
      exit 1
      ;;
  esac
}

changed_files() {
  local worktree="$1"
  (
    cd "$worktree"
    git diff --name-only
    git diff --cached --name-only
    git ls-files --others --exclude-standard
  ) | sed '/^$/d' | sort -u | while IFS= read -r file; do
    if is_dependency_symlink "$worktree" "$file"; then
      continue
    fi
    echo "$file"
  done
}

is_dependency_symlink() {
  local worktree="$1"
  local file="$2"
  case "$file" in
    node_modules|*/node_modules|vendor|vendor/bundle)
      [ -L "$worktree/$file" ] && return 0
      ;;
  esac
  return 1
}

unstage_dependency_symlinks() {
  local worktree="$1"
  (
    cd "$worktree"
    while IFS= read -r file; do
      if is_dependency_symlink "$worktree" "$file"; then
        git rm --cached -q -- "$file" 2>/dev/null || true
      fi
    done < <(git diff --cached --name-only)
  )
}

is_redline_path() {
  local file="$1"
  case "$file" in
    docs/modules/*/tasks/*.md) return 0 ;;
    docs/modules/*/.work-meta.json) return 0 ;;
    .claude/scripts|$HOME/.pmai/scripts/*) return 0 ;;
    .claude/skills|.claude/skills/*) return 0 ;;
    .claude/settings.json) return 0 ;;
  esac
  return 1
}

check_redlines() {
  local worktree="$1"
  local bad=()
  local f
  while IFS= read -r f; do
    if is_redline_path "$f"; then
      bad+=("$f")
    fi
  done < <(changed_files "$worktree")

  if [ "${#bad[@]}" -gt 0 ]; then
    echo "错误：/pmai-quick-fix 命中红线，拒绝继续：" >&2
    printf '  - %s\n' "${bad[@]}" >&2
    return 1
  fi
}

check_preflight_redlines() {
  local check_root="$1"  # main mode 传主仓根，build mode 传 build worktree
  local bad=()
  local line status file
  while IFS= read -r line; do
    status="${line:0:2}"
    file="${line:3}"
    case "$status" in
      R*|C*) file="${file#* -> }" ;;
    esac
    if is_redline_path "$file"; then
      bad+=("$file")
    fi
  done < <(git -C "$check_root" status --porcelain)

  if [ "${#bad[@]}" -gt 0 ]; then
    echo "错误：base worktree ($check_root) 当前已有红线路径改动，/pmai-quick-fix 拒绝启动：" >&2
    printf '  - %s\n' "${bad[@]}" >&2
    return 1
  fi
}

warn_active_work() {
  local repo_root="$1"
  local found=()
  local meta work_dir status id
  shopt -s nullglob
  # 主仓 + 所有 attached 的 build worktree（不假设在 .worktrees/，问 git）
  local _wt_paths=("$repo_root")
  while IFS=$'\t' read -r _wt_branch _wt_path; do
    [ -n "$_wt_path" ] && _wt_paths+=("$_wt_path")
  done < <(list_worktrees_by_branch_prefix "build-" "$repo_root" 2>/dev/null)
  local _wt
  for _wt in "${_wt_paths[@]}"; do
    [ -d "$_wt" ] || continue
    # 真相源 = docs/modules/<模块>/.work-meta.json。
    for meta in "$_wt"/docs/modules/*/.work-meta.json; do
      [ -f "$meta" ] || continue
      status=$(python3 - "$meta" <<'PY' 2>/dev/null || true
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("status", ""))
PY
)
      if [ "$status" = "active" ]; then
        id=$(python3 - "$meta" <<'PY' 2>/dev/null || true
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8")).get("id", "unknown"))
PY
)
        work_dir=$(dirname "$meta")
        found+=("$id ($work_dir)")
      fi
    done
  done
  shopt -u nullglob

  if [ "${#found[@]}" -gt 0 ]; then
    echo "警告：当前有活跃 work，ff-only merge 可能需要自动 rebase：" >&2
    printf '  - %s\n' "${found[@]}" >&2
  fi
}

warn_leftovers() {
  local repo_root="$1"
  shopt -s nullglob
  local leftovers=("$repo_root"/.worktrees/tmp-quick-*)
  shopt -u nullglob
  if [ "${#leftovers[@]}" -gt 0 ]; then
    echo "提示：检测到残留 quick-fix worktree：" >&2
    printf '  - %s\n' "${leftovers[@]}" >&2
    echo "可运行：bash $HOME/.pmai/scripts/quick-fix.sh --cleanup" >&2
  fi
}

run_tsc_if_needed() {
  local worktree="$1"
  local skip_tsc="$2"
  local force="$3"
  local needs_tsc=false
  local f
  while IFS= read -r f; do
    case "$f" in
      *.ts|*.tsx|*.mts|*.cts) needs_tsc=true ;;
    esac
  done < <(changed_files "$worktree")

  if [ "$needs_tsc" != "true" ]; then
    return 0
  fi
  if [ "$skip_tsc" = "true" ]; then
    echo "跳过 tsc --noEmit（--skip-tsc）。"
    return 0
  fi

  echo "检测到 TypeScript 改动，运行 tsc --noEmit..."
  set +e
  (
    cd "$worktree"
    if [ -x "./node_modules/.bin/tsc" ]; then
      ./node_modules/.bin/tsc --noEmit
    elif command -v bun >/dev/null 2>&1; then
      bun tsc --noEmit
    elif command -v npx >/dev/null 2>&1; then
      npx tsc --noEmit
    else
      echo "错误：未找到 tsc（node_modules/.bin/tsc、bun、npx 均不可用）。" >&2
      exit 127
    fi
  )
  local rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    if [ "$force" = "true" ]; then
      echo "警告：tsc 失败，但 --force 已指定，继续 merge。" >&2
      return 0
    fi
    echo "错误：tsc --noEmit 失败。可重改、取消，或用 --force 强制通过。" >&2
    return "$rc"
  fi
}

confirm_diff() {
  local worktree="$1"
  case "${QUICK_FIX_DECISION:-}" in
    pass|approve|yes|通过) return 0 ;;
    redo|重做)
      echo "已保留 worktree：$worktree" >&2
      return 3
      ;;
    cancel|取消) return 4 ;;
    "") ;;
    *) echo "错误：未知 QUICK_FIX_DECISION=${QUICK_FIX_DECISION}" >&2; return 2 ;;
  esac

  if [ "${QUICK_FIX_APPROVE:-}" = "1" ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    echo "错误：非交互环境未设置 QUICK_FIX_APPROVE=1，无法完成 PM 审批。" >&2
    return 2
  fi

  local answer
  while true; do
    printf "PM 审批 diff：输入“通过”继续，“重做”保留 worktree，“取消”清理退出: " >&2
    IFS= read -r answer
    case "$answer" in
      通过|pass|approve|yes|y|Y) return 0 ;;
      重做|redo|r|R)
        echo "已保留 worktree：$worktree" >&2
        return 3
        ;;
      取消|cancel|c|C) return 4 ;;
      *) echo "请输入：通过 / 重做 / 取消" >&2 ;;
    esac
  done
}

cleanup_branch() {
  local repo_root="$1"
  local branch="$2"
  local force="${3:-false}"
  local worktree="$repo_root/.worktrees/$branch"

  if [[ "$branch" != tmp-quick-* ]]; then
    echo "错误：只能清理 tmp-quick-* 分支: $branch" >&2
    return 1
  fi

  local listed
  listed=$(git -C "$repo_root" worktree list --porcelain | awk -v b="refs/heads/$branch" '
    $1 == "worktree" { wt=$2 }
    $1 == "branch" && $2 == b { print wt }
  ' | head -1)
  if [ -n "$listed" ]; then
    worktree="$listed"
  fi

  if [ -d "$worktree" ] || [ -n "$listed" ]; then
    local status_count=0
    if [ -d "$worktree" ]; then
      status_count=$(git -C "$worktree" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$status_count" != "0" ]; then
      echo "警告：$branch 有 $status_count 条未提交改动，将强制清理。" >&2
    fi
    git -C "$repo_root" worktree remove --force "$worktree" 2>/dev/null || rm -rf "$worktree"
  fi

  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
    if [ "$force" = "true" ]; then
      git -C "$repo_root" branch -D "$branch" >/dev/null
    else
      git -C "$repo_root" branch -d "$branch" >/dev/null
    fi
  fi
}

cmd_cancel() {
  local repo_root="$1"
  local branch="${2:-}"
  [ -n "$branch" ] || usage
  cleanup_branch "$repo_root" "$branch" true
  echo "已取消并清理：$branch"
}

cmd_cleanup() {
  local repo_root="$1"
  local branches=()
  local b
  while IFS= read -r b; do
    branches+=("$b")
  done < <(
    {
      git -C "$repo_root" for-each-ref --format='%(refname:short)' refs/heads/tmp-quick-* 2>/dev/null
      find "$repo_root/.worktrees" -maxdepth 1 -type d -name 'tmp-quick-*' -exec basename {} \; 2>/dev/null
    } | sort -u
  )

  if [ "${#branches[@]}" -eq 0 ]; then
    echo "没有残留 tmp-quick-* worktree。"
    return 0
  fi

  echo "将清理以下 quick-fix 残留："
  for b in "${branches[@]}"; do
    local wt="$repo_root/.worktrees/$b"
    local count="?"
    if [ -d "$wt" ]; then
      count=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    fi
    echo "  - ${b}（未提交改动: ${count}）"
  done

  if [ "${QUICK_FIX_ASSUME_YES:-}" != "1" ]; then
    if [ ! -t 0 ]; then
      echo "错误：非交互环境未设置 QUICK_FIX_ASSUME_YES=1，拒绝批量清理。" >&2
      return 2
    fi
    local answer
    printf "确认清理？输入 yes 继续: " >&2
    IFS= read -r answer
    [ "$answer" = "yes" ] || [ "$answer" = "通过" ] || {
      echo "已取消清理。"
      return 0
    }
  fi

  for b in "${branches[@]}"; do
    cleanup_branch "$repo_root" "$b" true
  done
  echo "quick-fix 残留清理完成。"
}

cmd_history() {
  local repo_root="$1"
  local n="${2:-10}"
  case "$n" in
    ''|*[!0-9]*) echo "错误：history N 必须是数字。" >&2; return 1 ;;
  esac
  git -C "$repo_root" log --grep '^\[quick-fix\]' --format='%h %ci %s' -"${n}"
}

cmd_snapshot() {
  local repo_root="$1"
  local snapshot="$repo_root/QUICKFIX_LOG.md"
  {
    echo "# Quick Fix History"
    echo
    echo "生成时间：$(date '+%Y-%m-%d %H:%M:%S %z')"
    echo
    echo '```'
    git -C "$repo_root" log --grep '^\[quick-fix\]' --format='%h %ci %s'
    echo '```'
  } >"$snapshot"

  if [ -z "$(git -C "$repo_root" status --porcelain -- QUICKFIX_LOG.md)" ]; then
    echo "QUICKFIX_LOG.md 无变化。"
    return 0
  fi
  git -C "$repo_root" add QUICKFIX_LOG.md
  git -C "$repo_root" commit -m "docs: 生成 quick-fix 历史快照"
}

commit_and_merge() {
  local repo_root="$1"
  local worktree="$2"
  local branch="$3"
  local desc="$4"
  local base_branch="$5"     # main mode: "main"; build mode: "build-*"
  local base_worktree="$6"   # main mode: repo_root; build mode: build worktree path

  (
    cd "$worktree"
    git add -A
    unstage_dependency_symlinks "$worktree"
    if git diff --cached --quiet; then
      echo "错误：没有检测到可提交改动。" >&2
      exit 1
    fi

    local files shortstat insertions deletions
    files=$(git diff --cached --name-only | paste -sd ', ' -)
    shortstat=$(git diff --cached --numstat | awk '
      $1 ~ /^[0-9]+$/ { add += $1 }
      $2 ~ /^[0-9]+$/ { del += $2 }
      END { printf("+%d -%d 行", add, del) }
    ')
    insertions="$shortstat"
    deletions=""

    git commit -m "[quick-fix] $desc" \
      -m "目标: $files" \
      -m "变更: $insertions$deletions" \
      -m "临时分支: $branch" \
      -m "base 分支: $base_branch"

    local change_sha
    change_sha=$(git rev-parse --short HEAD)
    git commit --allow-empty -m "[quick-fix-log] $change_sha $desc"
  )

  if git -C "$base_worktree" merge --ff-only "$branch"; then
    # force=true: merge 已成功，repo_root 的 HEAD（main）可能不含 tmp 分支（build mode 时），
    # 此时 `branch -d` 的 merged-into-HEAD 检查会误判，直接 -D
    cleanup_branch "$repo_root" "$branch" true
    echo "quick-fix 已合并到 ${base_branch}：${branch}"
    return 0
  fi

  echo "ff-only merge 失败（target=${base_branch}），尝试在 tmp worktree 内 rebase ${base_branch} 后重试..." >&2
  if (
    cd "$worktree"
    git branch -D _tmp_base >/dev/null 2>&1 || true
    git fetch . "$base_branch":_tmp_base
    git rebase _tmp_base
    git branch -D _tmp_base >/dev/null 2>&1 || true
  ); then
    if git -C "$base_worktree" merge --ff-only "$branch"; then
      cleanup_branch "$repo_root" "$branch" true
      echo "quick-fix rebase 后已合并到 ${base_branch}：${branch}"
      return 0
    fi
  fi

  cat >&2 <<EOF
merge 失败（rebase 冲突或 retry 失败）。worktree 保留在 ${worktree}。
base 分支：${base_branch}（位于 ${base_worktree}）
可选：
  1. 手工解决冲突：cd ${worktree} && git rebase --continue
  2. 放弃本次 quick-fix：bash $HOME/.pmai/scripts/quick-fix.sh --cancel ${branch}
EOF
  return 1
}

cmd_main() {
  local repo_root="$1"
  local skip_tsc="$2"
  local force="$3"
  local raw_desc="$4"
  local desc
  desc=$(sanitize_desc "$raw_desc")
  if [ -z "$desc" ]; then
    echo "错误：desc sanitize 后为空。" >&2
    exit 1
  fi

  # 设置 BASE_BRANCH / BASE_WORKTREE（全局）
  ensure_quickfix_root "$repo_root"
  check_preflight_redlines "$BASE_WORKTREE"
  warn_active_work "$repo_root"
  warn_leftovers "$repo_root"

  local base_head ts branch worktree worktree_parent
  base_head=$(git -C "$repo_root" rev-parse "$BASE_BRANCH")
  ts="$(date +%Y%m%d-%H%M%S)-$$"
  branch="tmp-quick-$ts"
  worktree_parent=$(realpath_m "$repo_root/.worktrees")
  worktree=$(realpath_m "$repo_root/.worktrees/$branch")
  case "$worktree" in
    "$worktree_parent"/*) ;;
    *) echo "worktree 路径逃逸: $worktree" >&2; exit 1 ;;
  esac

  mkdir -p "$worktree_parent"
  git -C "$repo_root" worktree add -b "$branch" "$worktree" "$BASE_BRANCH"
  setup_dependency_symlinks "$repo_root" "$worktree"

  echo "BASE_BRANCH: $BASE_BRANCH"
  echo "BASE_HEAD: $base_head"
  echo "BRANCH: $branch"
  echo "WORKTREE: $worktree"

  if [ -n "${QUICK_FIX_COMMAND:-}" ]; then
    (cd "$worktree" && bash -lc "$QUICK_FIX_COMMAND")
  elif [ -t 0 ]; then
    echo "请在 worktree 内完成改动：$worktree"
    printf "完成后按 Enter 继续；输入 cancel 取消: " >&2
    local ready
    IFS= read -r ready
    if [ "$ready" = "cancel" ] || [ "$ready" = "取消" ]; then
      cleanup_branch "$repo_root" "$branch" true
      echo "已取消。"
      return 0
    fi
  else
    echo "错误：未提供 QUICK_FIX_COMMAND，且当前不是交互终端。" >&2
    cleanup_branch "$repo_root" "$branch" true
    return 2
  fi

  if ! check_redlines "$worktree"; then
    cleanup_branch "$repo_root" "$branch" true
    return 1
  fi

  if ! run_tsc_if_needed "$worktree" "$skip_tsc" "$force"; then
    echo "worktree 保留在：$worktree" >&2
    return 1
  fi

  if [ -z "$(changed_files "$worktree")" ]; then
    echo "错误：没有检测到改动。" >&2
    cleanup_branch "$repo_root" "$branch" true
    return 1
  fi

  echo
  echo "===== quick-fix diff ====="
  git -C "$worktree" diff --stat
  git -C "$worktree" diff
  local untracked
  untracked=$(git -C "$worktree" ls-files --others --exclude-standard)
  if [ -n "$untracked" ]; then
    echo
    echo "===== untracked files ====="
    printf '%s\n' "$untracked"
  fi
  echo "===== end diff ====="

  local decision_rc=0
  confirm_diff "$worktree" || decision_rc=$?
  case "$decision_rc" in
    0) ;;
    3) return 3 ;;
    4) cleanup_branch "$repo_root" "$branch" true; echo "已取消。"; return 0 ;;
    *) return "$decision_rc" ;;
  esac

  commit_and_merge "$repo_root" "$worktree" "$branch" "$desc" "$BASE_BRANCH" "$BASE_WORKTREE"
}

main() {
  local repo_root
  repo_root=$(find_main_repo_root)

  local skip_tsc=false
  local force=false
  local args=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --skip-tsc) skip_tsc=true; shift ;;
      --force) force=true; shift ;;
      --cancel) shift; cmd_cancel "$repo_root" "${1:-}"; exit $? ;;
      --cleanup) cmd_cleanup "$repo_root"; exit $? ;;
      --history) shift; cmd_history "$repo_root" "${1:-10}"; exit $? ;;
      --snapshot) cmd_snapshot "$repo_root"; exit $? ;;
      -h|--help) usage ;;
      --) shift; break ;;
      -*) echo "错误：未知参数 $1" >&2; usage ;;
      *) args+=("$1"); shift ;;
    esac
  done

  if [ "${#args[@]}" -ne 1 ]; then
    usage
  fi
  cmd_main "$repo_root" "$skip_tsc" "$force" "${args[0]}"
}

main "$@"
