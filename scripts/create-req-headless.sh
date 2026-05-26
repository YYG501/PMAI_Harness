#!/usr/bin/env bash
# create-req-headless.sh — non-interactive req state writer used by /new-req and CI smoke tests.
set -euo pipefail

usage() {
  cat <<'EOF'
用法:
  bash create-req-headless.sh --title <title> [options]

常用:
  bash $HOME/.pmai/scripts/create-req-headless.sh \
    --title "DX smoke requirement" \
    --brief "Build a minimal demo flow"

参数:
  --title <text>       需求标题，用于生成 slug 与默认 brief
  --brief <text>       brief.md 内容；不传时使用 title 写一个最小 brief
  --brief-file <path>  从文件复制 brief.md
  --slug <slug>        指定英文 kebab-case slug
  --req-id <id>        指定 req 分支名或短 id，如 req-001-demo / req-001
  --repo-root <path>   指定业务仓根目录；默认取当前 git 仓库主 worktree
  --no-brief           只创建 worktree、.req-meta.json、tasks/ 骨架，不写 brief.md
  --no-commit          不提交，供 /new-req 人工 brief 确认流程继续落盘
  -h, --help           显示帮助

输出:
  stdout 输出 JSON，包含 req_id、branch、worktree、req_dir、brief_path、commit。
EOF
}

die() {
  echo "❌ $*" >&2
  exit 2
}

need_value() {
  local flag="$1"
  local value="${2:-}"
  [ -n "$value" ] || die "$flag 需要参数值"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TITLE=""
BRIEF=""
BRIEF_FILE=""
SLUG=""
REQ_ARG=""
REPO_ROOT_ARG=""
NO_BRIEF=false
NO_COMMIT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --title)
      need_value "$1" "${2:-}"
      TITLE="$2"
      shift 2
      ;;
    --brief)
      need_value "$1" "${2:-}"
      BRIEF="$2"
      shift 2
      ;;
    --brief-file)
      need_value "$1" "${2:-}"
      BRIEF_FILE="$2"
      shift 2
      ;;
    --slug)
      need_value "$1" "${2:-}"
      SLUG="$2"
      shift 2
      ;;
    --req-id|--branch)
      need_value "$1" "${2:-}"
      REQ_ARG="$2"
      shift 2
      ;;
    --repo-root)
      need_value "$1" "${2:-}"
      REPO_ROOT_ARG="$2"
      shift 2
      ;;
    --no-brief)
      NO_BRIEF=true
      shift
      ;;
    --no-commit)
      NO_COMMIT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "未知参数: $1"
      ;;
    *)
      if [ -z "$TITLE" ]; then
        TITLE="$1"
        shift
      else
        die "未知位置参数: $1"
      fi
      ;;
  esac
done

[ -n "$TITLE" ] || die "缺少 --title"
[ -z "$BRIEF" ] || [ -z "$BRIEF_FILE" ] || die "--brief 与 --brief-file 只能二选一"
if [ "$NO_BRIEF" = true ] && { [ -n "$BRIEF" ] || [ -n "$BRIEF_FILE" ]; }; then
  die "--no-brief 不能同时传 --brief / --brief-file"
fi
if [ "$NO_BRIEF" = true ] && [ "$NO_COMMIT" != true ]; then
  die "--no-brief 必须同时传 --no-commit，避免提交没有 brief 的 stage 1"
fi

if [ -n "$REPO_ROOT_ARG" ]; then
  REPO_ROOT_INPUT="$(cd "$REPO_ROOT_ARG" && pwd)"
else
  REPO_ROOT_INPUT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -n "$REPO_ROOT_INPUT" ] || die "当前目录不在 git 仓库中，请传 --repo-root"

GIT_COMMON_DIR="$(git -C "$REPO_ROOT_INPUT" rev-parse --git-common-dir 2>/dev/null || true)"
[ -n "$GIT_COMMON_DIR" ] || die "无法读取 git common dir: $REPO_ROOT_INPUT"
GIT_COMMON_DIR="$(cd "$REPO_ROOT_INPUT" && cd "$GIT_COMMON_DIR" && pwd)"
if [[ "$GIT_COMMON_DIR" == */.git ]]; then
  REPO_ROOT="${GIT_COMMON_DIR%/.git}"
else
  REPO_ROOT="$(git -C "$REPO_ROOT_INPUT" rev-parse --show-toplevel 2>/dev/null || true)"
fi
[ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ] || die "无法确定主仓库根目录"

if [ -z "$SLUG" ]; then
  SLUG="$(TITLE="$TITLE" python3 - <<'PY'
import os
import re
import hashlib

raw = os.environ["TITLE"]
slug = re.sub(r"[^a-z0-9]+", "-", raw.lower()).strip("-")
parts = [p for p in slug.split("-") if p][:4]
result = "-".join(parts)
if not result:
    # 标题无 ASCII 词（如纯中文）→ 退化成裸 "req" 会让分支名变 req-NNN-req。
    # 改用标题的稳定 hash slug：同标题同 slug、不同标题不撞。
    result = "cn-" + hashlib.md5(raw.encode("utf-8")).hexdigest()[:8]
print(result)
PY
)"
fi

[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "--slug 必须是英文 kebab-case: $SLUG"

if [ -n "$REQ_ARG" ]; then
  if [[ "$REQ_ARG" =~ ^req-([0-9]{3,})(-([a-z0-9][a-z0-9-]*))?$ ]]; then
    NUM="${BASH_REMATCH[1]}"
    if [ -n "${BASH_REMATCH[3]:-}" ]; then
      SLUG="${BASH_REMATCH[3]}"
    fi
  else
    die "--req-id 必须类似 req-001 或 req-001-demo: $REQ_ARG"
  fi
else
  NUM="$(bash "$SCRIPT_DIR/_lib/req-num-resolver.sh" next "$REPO_ROOT")"
fi

REQ_ID="req-$NUM"
BRANCH="req-$NUM-$SLUG"

if ! WORKTREE_OUTPUT="$(cd "$REPO_ROOT" && bash "$SCRIPT_DIR/create-req-worktree.sh" "$BRANCH" 2>&1)"; then
  printf "%s\n" "$WORKTREE_OUTPUT" >&2
  exit 1
fi
WORKTREE_DIR="$(printf "%s\n" "$WORKTREE_OUTPUT" | tail -n 1)"
[ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ] || die "create-req-worktree.sh 未返回有效 worktree 路径"
WORKTREE_DIR="$(cd "$WORKTREE_DIR" && pwd)"

REQ_REL="requirements/active/$BRANCH"
REQ_DIR="$WORKTREE_DIR/$REQ_REL"
if [ -e "$REQ_DIR/.req-meta.json" ] || [ -e "$REQ_DIR/brief.md" ]; then
  die "req 已存在，拒绝覆盖: $REQ_DIR"
fi

mkdir -p "$REQ_DIR/tasks/_archived"
mkdir -p "$REQ_DIR/attachments"
touch "$REQ_DIR/attachments/.gitkeep"  # 跟 tasks/_archived 对称预建；PM IDE 一眼可见 attachments 机制存在（详见 skills/_shared/pm-view/attachments-upload.md）

WORKTREE_META="$(python3 - "$REPO_ROOT" "$WORKTREE_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
worktree = Path(sys.argv[2]).resolve()
try:
    print(worktree.relative_to(root).as_posix())
except ValueError:
    print(str(worktree))
PY
)"
ENTERED_AT="$(python3 - <<'PY'
from datetime import datetime
print(datetime.now().astimezone().isoformat(timespec="seconds"))
PY
)"

REQ_ID="$REQ_ID" \
REQ_NAME="$SLUG" \
BRANCH="$BRANCH" \
WORKTREE_META="$WORKTREE_META" \
ENTERED_AT="$ENTERED_AT" \
REQ_DIR="$REQ_DIR" \
python3 - <<'PY'
import json
import os
import tempfile
from pathlib import Path


def write_json_atomic(path: Path, data: dict) -> None:
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
        delete=False,
    ) as fh:
        tmp = Path(fh.name)
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, path)

req_dir = Path(os.environ["REQ_DIR"])
meta = {
    "id": os.environ["REQ_ID"],
    "name": os.environ["REQ_NAME"],
    "branch": os.environ["BRANCH"],
    "worktree": os.environ["WORKTREE_META"],
    "stage": 1,
    "stage_history": [
        {"stage": 1, "entered_at": os.environ["ENTERED_AT"]},
    ],
    "status": "active",
}
write_json_atomic(req_dir / ".req-meta.json", meta)
PY

BRIEF_PATH=""
if [ "$NO_BRIEF" != true ]; then
  BRIEF_PATH="$REQ_DIR/brief.md"
  if [ -n "$BRIEF_FILE" ]; then
    [ -f "$BRIEF_FILE" ] || die "--brief-file 不存在: $BRIEF_FILE"
    cp "$BRIEF_FILE" "$BRIEF_PATH"
  else
    [ -n "$BRIEF" ] || BRIEF="$TITLE"
    TITLE="$TITLE" BRIEF="$BRIEF" BRIEF_PATH="$BRIEF_PATH" python3 - <<'PY'
import os
from pathlib import Path

title = os.environ["TITLE"].strip()
brief = os.environ["BRIEF"].strip()
content = f"""# Brief

## 需求标题
{title}

## 需求描述
{brief}
"""
Path(os.environ["BRIEF_PATH"]).write_text(content, encoding="utf-8")
PY
  fi
fi

COMMIT=""
if [ "$NO_COMMIT" != true ]; then
  (
    cd "$WORKTREE_DIR"
    git add "$REQ_REL/.req-meta.json" "$REQ_REL/brief.md" "$REQ_REL/tasks"
    git commit -m "stage 1 brief: $BRANCH" >/dev/null
  )
  COMMIT="$(git -C "$WORKTREE_DIR" rev-parse --short HEAD)"
fi

REQ_ID="$REQ_ID" \
REQ_NAME="$SLUG" \
BRANCH="$BRANCH" \
WORKTREE_DIR="$WORKTREE_DIR" \
REQ_DIR="$REQ_DIR" \
REQ_REL="$REQ_REL" \
BRIEF_PATH="$BRIEF_PATH" \
COMMIT="$COMMIT" \
python3 - <<'PY'
import json
import os

commit = os.environ["COMMIT"] or None
brief_path = os.environ["BRIEF_PATH"] or None
payload = {
    "req_id": os.environ["REQ_ID"],
    "name": os.environ["REQ_NAME"],
    "branch": os.environ["BRANCH"],
    "worktree": os.environ["WORKTREE_DIR"],
    "req_dir": os.environ["REQ_DIR"],
    "req_rel": os.environ["REQ_REL"],
    "brief_path": brief_path,
    "committed": commit is not None,
    "commit": commit,
}
print(json.dumps(payload, ensure_ascii=False))
PY
