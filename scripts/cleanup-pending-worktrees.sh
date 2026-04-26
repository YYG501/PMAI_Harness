#!/usr/bin/env bash
# cleanup-pending-worktrees.sh — 清理由 close-task / close-req 标记的待清理 worktree + branch
# 用法: bash scripts/cleanup-pending-worktrees.sh [--dry-run]
#
# 背景：
# close-task / close-req 不再直接删 worktree/branch。原因是 PM 经常在被关闭的
# worktree 内（即 cwd = .worktrees/<branch>）执行 close，删除会让 Claude Code
# 父进程的 cwd 变成 dangling，下一次 Stop hook 的 posix_spawn 报 ENOENT。
# 解决办法是把删除推迟，由本脚本在主仓 cwd 的会话里统一执行。

set -euo pipefail

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# --- 主仓根目录 ---
GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
if [ -n "$GIT_COMMON" ] && [ "$GIT_COMMON" != ".git" ]; then
  REPO_ROOT=$(cd "$GIT_COMMON/.." && pwd)
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
fi

if [ -z "$REPO_ROOT" ]; then
  echo "❌ 不在 git 仓库内。" >&2
  exit 1
fi

PENDING_FILE="$REPO_ROOT/.runs/pending-cleanup.json"

if [ ! -f "$PENDING_FILE" ]; then
  echo "✅ 无待清理项。"
  exit 0
fi

COUNT=$(python3 -c "import json; print(len(json.load(open('$PENDING_FILE'))))" 2>/dev/null || echo 0)
if [ "$COUNT" = "0" ]; then
  echo "✅ 无待清理项。"
  exit 0
fi

# --- 安全：当前 cwd 不能在任何 pending worktree 内（同样会触发 dangling cwd） ---
CALLER_PWD="$(pwd -P 2>/dev/null || echo "")"
CONFLICT=$(python3 - "$PENDING_FILE" "$CALLER_PWD" <<'PY'
import json, os, sys
pending_file, caller = sys.argv[1], sys.argv[2]
caller = os.path.realpath(caller) if caller else ""
with open(pending_file) as f:
    entries = json.load(f)
hits = []
for e in entries:
    wt = e.get("worktree", "")
    if not wt:
        continue
    if not os.path.exists(wt):
        continue
    real = os.path.realpath(wt)
    if caller == real or caller.startswith(real + os.sep):
        hits.append(wt)
if hits:
    print("\n".join(hits))
PY
)

if [ -n "$CONFLICT" ]; then
  echo "❌ 当前 cwd 在以下待清理 worktree 内：" >&2
  echo "$CONFLICT" | sed 's/^/   /' >&2
  echo "" >&2
  echo "   清理这些 worktree 会让当前 Claude Code 进程 cwd 变成 dangling。" >&2
  echo "   请退出当前会话，在主仓 ($REPO_ROOT) 重新打开 Claude Code 后再跑 cleanup。" >&2
  exit 1
fi

echo "🧹 待清理项: $COUNT"

# --- 遍历 entries：成功清理的从列表移除，失败的保留 ---
TMP_RESULT=$(mktemp)
trap 'rm -f "$TMP_RESULT"' EXIT

python3 - "$PENDING_FILE" "$REPO_ROOT" "$DRY_RUN" "$TMP_RESULT" <<'PY'
import json, os, subprocess, sys

pending_file, repo_root, dry_run_str, result_path = sys.argv[1:5]
dry_run = dry_run_str == "true"

with open(pending_file) as f:
    entries = json.load(f)

remaining = []
ok_count = 0
fail_count = 0

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

for e in entries:
    branch = e.get("branch", "")
    worktree = e.get("worktree", "")
    kind = e.get("kind", "?")
    label = f"{kind} {branch}"

    if dry_run:
        print(f"  [dry-run] would clean {label}: worktree={worktree}")
        remaining.append(e)
        continue

    failed = False
    msg_parts = []

    # 1. 删 worktree（如果还在）
    if worktree and os.path.isdir(worktree):
        r = run(["git", "-C", repo_root, "worktree", "remove", worktree])
        if r.returncode != 0:
            # 回退：rm -rf + prune
            r2 = run(["rm", "-rf", worktree])
            if r2.returncode != 0:
                failed = True
                msg_parts.append(f"worktree remove failed: {r.stderr.strip() or r2.stderr.strip()}")
            else:
                run(["git", "-C", repo_root, "worktree", "prune"])
                msg_parts.append("worktree force-removed")
        else:
            msg_parts.append("worktree removed")
    elif worktree:
        # worktree 已不在磁盘，prune 残留 metadata
        run(["git", "-C", repo_root, "worktree", "prune"])
        msg_parts.append("worktree already gone")

    # 2. 删 branch（如果还在）
    if branch:
        check = run(["git", "-C", repo_root, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}"])
        if check.returncode == 0:
            r = run(["git", "-C", repo_root, "branch", "-D", branch])
            if r.returncode != 0:
                failed = True
                msg_parts.append(f"branch -D failed: {r.stderr.strip()}")
            else:
                msg_parts.append("branch deleted")
        else:
            msg_parts.append("branch already gone")

    if failed:
        fail_count += 1
        print(f"  ❌ {label}: {'; '.join(msg_parts)}")
        remaining.append(e)
    else:
        ok_count += 1
        print(f"  ✅ {label}: {'; '.join(msg_parts)}")

if not dry_run:
    if remaining:
        with open(pending_file, "w") as f:
            json.dump(remaining, f, indent=2, ensure_ascii=False)
    else:
        # 列表清空 → 删整个文件，避免误以为还有待清理
        try:
            os.remove(pending_file)
        except FileNotFoundError:
            pass

with open(result_path, "w") as f:
    json.dump({"ok": ok_count, "fail": fail_count, "remaining": len(remaining)}, f)
PY

OK=$(python3 -c "import json; print(json.load(open('$TMP_RESULT'))['ok'])")
FAIL=$(python3 -c "import json; print(json.load(open('$TMP_RESULT'))['fail'])")

if [ "$DRY_RUN" = "true" ]; then
  echo "（dry-run；未做任何改动）"
  exit 0
fi

echo ""
echo "完成：成功 $OK / 失败 $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "⚠️ 有未清理项保留在 $PENDING_FILE。请人工检查。" >&2
  exit 1
fi
