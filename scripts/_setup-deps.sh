#!/usr/bin/env bash
# _setup-deps.sh — 依赖 symlink + 端口推导工具函数库（供 create-task-worktree.sh / quick-fix.sh 共用）
#
# 用法: source 本文件后调用三个函数，均不修改调用方 set -e 状态：
#   symlink_if_exists <src> <dst>
#     若 src 存在且 dst 不存在，则 mkdir -p dst 的父目录，再 ln -s src dst。
#
#   setup_dependency_symlinks <repo_root> <worktree_dir>
#     根据 repo_root 根的包管理配置给 worktree_dir 装 symlink：
#       package.json → node_modules（含 monorepo 递归 max-depth 4）
#       Gemfile      → vendor/bundle
#       go.mod       → vendor
#
#   derive_task_port <repo_root> <task_basename>
#     基于 repo_root 的 realpath hash 推导基础端口（3000-9999），+ task_num 后 echo。

symlink_if_exists() {
  local src="$1"
  local dst="$2"
  if [ -d "$src" ] && [ ! -e "$dst" ]; then
    mkdir -p "$(dirname "$dst")"
    ln -s "$src" "$dst"
  fi
}

setup_dependency_symlinks() {
  local repo_root="$1"
  local worktree_dir="$2"

  if [ -f "$repo_root/package.json" ]; then
    symlink_if_exists "$repo_root/node_modules" "$worktree_dir/node_modules"
  fi

  if [ -f "$repo_root/Gemfile" ]; then
    symlink_if_exists "$repo_root/vendor/bundle" "$worktree_dir/vendor/bundle"
  fi

  if [ -f "$repo_root/go.mod" ]; then
    symlink_if_exists "$repo_root/vendor" "$worktree_dir/vendor"
  fi

  # Monorepo 递归 symlink：max-depth 4，跳过 worktrees 和嵌套 node_modules
  if [ -f "$repo_root/package.json" ]; then
    find "$repo_root" -maxdepth 4 -name "node_modules" -type d \
      -not -path "*/.worktrees/*" \
      -not -path "*/node_modules/*/node_modules" \
      2>/dev/null | while read -r nm_path; do
      local rel="${nm_path#"$repo_root"/}"
      local target="$worktree_dir/$rel"
      if [ ! -e "$target" ]; then
        mkdir -p "$(dirname "$target")"
        ln -s "$nm_path" "$target"
      fi
    done
  fi
}

derive_base_port() {
  local repo_root="$1"

  python3 -c "
import hashlib, os
project_path = os.path.realpath('$repo_root')
h = int(hashlib.md5(project_path.encode()).hexdigest(), 16)
print(3000 + (h % 7000))
" 2>/dev/null || echo "3000"
}

derive_task_port() {
  local repo_root="$1"
  local task_basename="$2"

  local base_port task_num
  base_port=$(derive_base_port "$repo_root")
  task_num=$(echo "$task_basename" | grep -oE 'task-([0-9]+)' | grep -oE '[0-9]+' | sed 's/^0*//' || true)
  if [ -z "$task_num" ]; then
    task_num=0
  fi

  echo $((base_port + task_num))
}

# Backward-compatible aliases for callers that use the names from the initial extraction.
setup_deps_symlink_if_exists() {
  symlink_if_exists "$@"
}

setup_deps_install_symlinks() {
  setup_dependency_symlinks "$@"
}

setup_deps_derive_port() {
  local repo_root="$1"
  local task_num="${2:-0}"
  local base_port
  base_port=$(derive_base_port "$repo_root")
  echo $((base_port + task_num))
}
