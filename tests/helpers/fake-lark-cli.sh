#!/usr/bin/env bash
# Fake lark-cli for unit-testing _lib/lark_adapter without hitting real lark API.
#
# 行为可通过环境变量调节：
#   FAKE_LARK_LOG  — 把每次调用 (argv + pwd + --markdown 真实 cell 内容) 写进该文件
#   FAKE_LARK_VERSION         — 默认 "lark-cli 1.0.27"
#   FAKE_LARK_AUTH_STATUS_RC  — 默认 0
#   FAKE_LARK_AUTH_CHECK_RC   — 默认 0
#   FAKE_LARK_DOCS_CREATE_OUT — 默认 {"data":{"doc_id":"docX1","doc_url":"https://x"}}
#   FAKE_LARK_DOCS_FETCH_OUT  — 默认带 document_id / revision_id / content 的读取结果
#   FAKE_LARK_DOCS_UPDATE_RC  — 默认 0
#   FAKE_LARK_DOCS_UPDATE_OUT — 默认返回 revision 7
#   FAKE_LARK_COMMENTS_OUT    — 默认空评论页
#   FAKE_LARK_REPLIES_OUT     — 默认空回复页
#   FAKE_LARK_REPLY_CREATE_OUT — 默认返回新回复 ID 与作者
#   FAKE_LARK_COMMENT_PATCH_OUT — 默认成功切换评论状态
#   FAKE_LARK_API_OUT         — 默认 {"data":{"items":[],"page_token":null}}
set -u

# Defaults pre-assigned so `}` chars don't accidentally terminate `${VAR:-...}`
# parameter expansions inside case branches.
_DEFAULT_VERSION='lark-cli 1.0.27'
_DEFAULT_DOCS_CREATE_OUT='{"data":{"doc_id":"docX1","doc_url":"https://x","document":{"document_id":"docX1","revision_id":7}}}'
_DEFAULT_DOCS_FETCH_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","revision_id":7,"content":"# Hello\n\n正文 first time。\n"}}}'
_DEFAULT_DOCS_UPDATE_OUT='{"ok":true,"data":{"document":{"document_id":"docX1","revision_id":7},"result":"success","updated_blocks_count":1,"warnings":[]}}'
_DEFAULT_COMMENTS_OUT='{"ok":true,"data":{"items":[],"has_more":false}}'
_DEFAULT_REPLIES_OUT='{"ok":true,"data":{"items":[],"has_more":false}}'
_DEFAULT_REPLY_CREATE_OUT='{"ok":true,"data":{"reply_id":"r-result","user_id":"ou-agent","create_time":260,"update_time":260}}'
_DEFAULT_COMMENT_PATCH_OUT='{"ok":true,"data":{"comment_id":"c1","is_solved":false}}'
_DEFAULT_API_OUT='{"data":{"items":[],"page_token":null}}'

if [ -n "${FAKE_LARK_LOG:-}" ]; then
  # 记录 cmdline + cwd
  {
    echo "ARGV: $*"
    echo "CWD: $(pwd)"
    for arg in "$@"; do
      case "$arg" in
        @./*)
          fname="${arg#@./}"
          if [ -f "$fname" ]; then
            echo "MARKDOWN_RESOLVED: $(cd "$(dirname "$fname")" && pwd)/$fname"
            echo "MARKDOWN_HEAD: $(head -1 "$fname" 2>/dev/null || echo MISSING)"
          else
            echo "MARKDOWN_MISSING: $fname"
          fi
          ;;
      esac
    done
    echo "---"
  } >> "$FAKE_LARK_LOG"
fi

case "${1:-}" in
  --version)
    echo "${FAKE_LARK_VERSION:-$_DEFAULT_VERSION}"
    exit 0
    ;;
  auth)
    case "${2:-}" in
      status)
        exit "${FAKE_LARK_AUTH_STATUS_RC:-0}"
        ;;
      check)
        exit "${FAKE_LARK_AUTH_CHECK_RC:-0}"
        ;;
    esac
    ;;
  docs)
    case "${2:-}" in
      +create)
        printf '%s' "${FAKE_LARK_DOCS_CREATE_OUT:-$_DEFAULT_DOCS_CREATE_OUT}"
        exit 0
        ;;
      +update)
        printf '%s' "${FAKE_LARK_DOCS_UPDATE_OUT:-$_DEFAULT_DOCS_UPDATE_OUT}"
        exit "${FAKE_LARK_DOCS_UPDATE_RC:-0}"
        ;;
      +fetch)
        if [ -n "${FAKE_LARK_MUTATE_FILE:-}" ]; then
          printf '\n%s\n' "${FAKE_LARK_MUTATE_CONTENT:-concurrent local edit}" \
            >> "$FAKE_LARK_MUTATE_FILE"
        fi
        printf '%s' "${FAKE_LARK_DOCS_FETCH_OUT:-$_DEFAULT_DOCS_FETCH_OUT}"
        exit 0
        ;;
    esac
    ;;
  drive)
    case "${2:-} ${3:-}" in
      "file.comments list")
        printf '%s' "${FAKE_LARK_COMMENTS_OUT:-$_DEFAULT_COMMENTS_OUT}"
        exit 0
        ;;
      "file.comment.replys list")
        printf '%s' "${FAKE_LARK_REPLIES_OUT:-$_DEFAULT_REPLIES_OUT}"
        exit 0
        ;;
      "file.comment.replys create")
        printf '%s' "${FAKE_LARK_REPLY_CREATE_OUT:-$_DEFAULT_REPLY_CREATE_OUT}"
        exit 0
        ;;
      "file.comments patch")
        printf '%s' "${FAKE_LARK_COMMENT_PATCH_OUT:-$_DEFAULT_COMMENT_PATCH_OUT}"
        exit 0
        ;;
    esac
    ;;
  api)
    printf '%s' "${FAKE_LARK_API_OUT:-$_DEFAULT_API_OUT}"
    exit 0
    ;;
esac

echo "fake-lark-cli: unhandled $*" >&2
exit 2
