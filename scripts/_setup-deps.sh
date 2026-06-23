#!/usr/bin/env bash
# _setup-deps.sh — worktree 依赖 symlink 工具函数库（供 build/quick-fix worktree 共用）
#
# 用法: source 本文件后调用函数，均不修改调用方 set -e 状态：
#   symlink_if_exists <src> <dst>
#     若 src 存在且 dst 不存在，则 mkdir -p dst 的父目录，再 ln -s src dst。
#
#   setup_dependency_symlinks <repo_root> <worktree_dir>
#     根据 repo_root 的包管理配置给 worktree_dir 装 symlink：
#       package.json → 同目录 node_modules（任意深度，prune 构建产物 / .git /
#                      .worktrees / 已存在 node_modules；覆盖根级、monorepo、
#                      子目录项目如 prototypes/）
#       Gemfile      → vendor/bundle（仅根级）
#       go.mod       → vendor（仅根级）

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

  # Ruby / Go：根级守门保留（这两个生态约定项目根有 Gemfile/go.mod）
  if [ -f "$repo_root/Gemfile" ]; then
    symlink_if_exists "$repo_root/vendor/bundle" "$worktree_dir/vendor/bundle"
  fi

  if [ -f "$repo_root/go.mod" ]; then
    symlink_if_exists "$repo_root/vendor" "$worktree_dir/vendor"
  fi

  # Node：对仓库里**任意深度**的 package.json 都尝试 link 同目录 node_modules。
  # 不再用"根有 package.json"作为前置——常见模式如 prototypes/、apps/web/、
  # packages/foo/ 等子目录项目，根没有 package.json 也要覆盖（否则 codex /
  # cursor-agent 在 worktree 跑测试时全找不到依赖）。
  # 用 prune 跳过会引发无谓递归或返回脏数据的目录（.git / .worktrees / 已存在
  # 的 node_modules / 构建输出 / venv）。
  find "$repo_root" \
    \( -name .git -o -name .worktrees -o -name node_modules \
       -o -name .next -o -name dist -o -name build -o -name .venv \) -prune \
    -o -type f -name package.json -print 2>/dev/null | while read -r pkg; do
    local pkg_dir="${pkg%/package.json}"
    local src="$pkg_dir/node_modules"
    local rel="${pkg_dir#"$repo_root"}"
    rel="${rel#/}"
    local dst
    if [ -z "$rel" ]; then
      dst="$worktree_dir/node_modules"
    else
      dst="$worktree_dir/$rel/node_modules"
    fi
    symlink_if_exists "$src" "$dst"
  done
}

# Backward-compatible aliases for callers that use the names from the initial extraction.
setup_deps_symlink_if_exists() {
  symlink_if_exists "$@"
}

setup_deps_install_symlinks() {
  setup_dependency_symlinks "$@"
}
