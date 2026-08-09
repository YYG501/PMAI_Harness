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
#   FAKE_LARK_DOCS_UPDATE_EMPTY — 为 1 时 update 成功退出但 stdout 为空
#   FAKE_LARK_ECHO_STDIN_ON_ERROR — update 失败时把收到的 stdin 回显到 stderr
#   FAKE_LARK_ECHO_STDIN_AS_DOCS_OUTPUT — docs 命令成功时把 stdin 当 stdout 回显
#   FAKE_LARK_COMMENTS_OUT    — 默认空评论页
#   FAKE_LARK_REPLIES_OUT     — 默认空回复页
#   FAKE_LARK_REPLY_CREATE_OUT — 默认返回新回复 ID 与作者
#   FAKE_LARK_COMMENT_PATCH_OUT — 默认成功切换评论状态
#   FAKE_LARK_API_OUT         — 默认 {"data":{"items":[],"page_token":null}}
#   FAKE_LARK_REBIND_PARENT / _HELD / _TARGET — docs +fetch 时把父目录改向
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

_FAKE_CONTENT_STDIN=0
_FAKE_EXPECT_CONTENT=0
for arg in "$@"; do
  if [ "$_FAKE_EXPECT_CONTENT" -eq 1 ]; then
    if [ "$arg" = "-" ]; then
      _FAKE_CONTENT_STDIN=1
    fi
    _FAKE_EXPECT_CONTENT=0
  elif [ "$arg" = "--content" ]; then
    _FAKE_EXPECT_CONTENT=1
  fi
done

_FAKE_STDIN_CONTENT=""
if [ "$_FAKE_CONTENT_STDIN" -eq 1 ]; then
  _FAKE_STDIN_CONTENT=$(cat)
fi

if [ -n "${FAKE_LARK_LOG:-}" ]; then
  # 记录 cmdline + cwd
  {
    echo "ARGV: $*"
    echo "CWD: $(pwd)"
    if [ "$_FAKE_CONTENT_STDIN" -eq 1 ]; then
      echo "STDIN_HEAD: ${_FAKE_STDIN_CONTENT%%$'\n'*}"
    fi
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
        if [ "${FAKE_LARK_ECHO_STDIN_AS_DOCS_OUTPUT:-0}" -eq 1 ]; then
          printf '%s' "$_FAKE_STDIN_CONTENT"
        else
          printf '%s' "${FAKE_LARK_DOCS_CREATE_OUT:-$_DEFAULT_DOCS_CREATE_OUT}"
        fi
        exit 0
        ;;
      +update)
        if [ "${FAKE_LARK_DOCS_UPDATE_RC:-0}" -ne 0 ] \
          && [ "${FAKE_LARK_ECHO_STDIN_ON_ERROR:-0}" -eq 1 ]; then
          printf '%s' "$_FAKE_STDIN_CONTENT" >&2
        fi
        if [ "${FAKE_LARK_DOCS_UPDATE_EMPTY:-0}" -eq 1 ]; then
          :
        elif [ "${FAKE_LARK_ECHO_STDIN_AS_DOCS_OUTPUT:-0}" -eq 1 ]; then
          printf '%s' "$_FAKE_STDIN_CONTENT"
        else
          printf '%s' "${FAKE_LARK_DOCS_UPDATE_OUT:-$_DEFAULT_DOCS_UPDATE_OUT}"
        fi
        exit "${FAKE_LARK_DOCS_UPDATE_RC:-0}"
        ;;
      +fetch)
        if [ -n "${FAKE_LARK_REBIND_PARENT:-}" ] \
          && [ -n "${FAKE_LARK_REBIND_HELD:-}" ] \
          && [ -n "${FAKE_LARK_REBIND_TARGET:-}" ] \
          && [ ! -e "$FAKE_LARK_REBIND_HELD" ]; then
          mv "$FAKE_LARK_REBIND_PARENT" "$FAKE_LARK_REBIND_HELD"
          ln -s "$FAKE_LARK_REBIND_TARGET" "$FAKE_LARK_REBIND_PARENT"
        fi
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
