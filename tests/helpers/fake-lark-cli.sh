#!/usr/bin/env bash
# Fake lark-cli for unit-testing _lib/lark_adapter without hitting real lark API.
#
# 行为可通过环境变量调节：
#   FAKE_LARK_LOG  — 把每次调用 (argv + pwd + --markdown 真实 cell 内容) 写进该文件
#   FAKE_LARK_VERSION         — 默认 "lark-cli 1.0.27"
#   FAKE_LARK_AUTH_STATUS_RC  — 默认 0
#   FAKE_LARK_AUTH_CHECK_RC   — 默认 0
#   FAKE_LARK_DOCS_CREATE_OUT — 默认 {"data":{"doc_id":"docX1","doc_url":"https://x"}}
#   FAKE_LARK_DOCS_UPDATE_RC  — 默认 0
#   FAKE_LARK_API_OUT         — 默认 {"data":{"items":[],"page_token":null}}
set -u

# Defaults pre-assigned so `}` chars don't accidentally terminate `${VAR:-...}`
# parameter expansions inside case branches.
_DEFAULT_VERSION='lark-cli 1.0.27'
_DEFAULT_DOCS_CREATE_OUT='{"data":{"doc_id":"docX1","doc_url":"https://x"}}'
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
        exit "${FAKE_LARK_DOCS_UPDATE_RC:-0}"
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
