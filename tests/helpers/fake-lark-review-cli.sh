#!/usr/bin/env bash
set -u

if [ -n "${FAKE_LARK_LOG:-}" ]; then
  printf 'ARGV: %s\n' "$*" >> "$FAKE_LARK_LOG"
fi

arg_after() {
  local wanted="$1"
  shift
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "$wanted" ]; then
      shift
      printf '%s' "${1:-}"
      return
    fi
    shift
  done
}

case "${1:-}" in
  --version)
    echo "${FAKE_REVIEW_VERSION:-lark-cli 1.0.63}"
    exit 0
    ;;
  auth)
    [ "${2:-}" = "status" ] && exit 0
    ;;
  docs)
    if [ "${2:-}" = "+fetch" ]; then
      format=$(arg_after --doc-format "$@")
      revision=$(arg_after --revision-id "$@")
      synced_revision="${FAKE_REVIEW_SYNCED_REVISION:-10}"
      if [ "$revision" = "7" ]; then
        if [ "${FAKE_REVIEW_FAIL_BASELINE:-0}" = "1" ]; then
          echo "baseline unavailable" >&2
          exit 1
        fi
        if [ "${FAKE_REVIEW_WRONG_BASELINE:-0}" = "1" ]; then
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":8,"content":"# Spec\n\nWrong baseline\n"}}}'
        else
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":7,"content":"# Spec\n\nOld rule\n"}}}'
        fi
      elif [ "${FAKE_REVIEW_SYNCED_REMOTE:-0}" = "1" ]; then
        if [ "$format" = "xml" ]; then
          if [ "${FAKE_REVIEW_FORMAT_LOSS:-0}" = "1" ]; then
            printf '%s' "{\"ok\":true,\"data\":{\"document\":{\"document_id\":\"docR\",\"revision_id\":$synced_revision,\"content\":\"<h1 id=\\\"b-title\\\">Spec</h1><p id=\\\"b-rule\\\">New rule</p>\",\"reference_map\":{}}}}"
          else
            printf '%s' "{\"ok\":true,\"data\":{\"document\":{\"document_id\":\"docR\",\"revision_id\":$synced_revision,\"content\":\"<h1 id=\\\"b-title\\\" align=\\\"left\\\">Spec</h1><p id=\\\"b-rule\\\" align=\\\"left\\\"><b>New rule</b></p><p id=\\\"b-repeat-1\\\">Repeat</p><p id=\\\"b-repeat-2\\\">Repeat</p><img id=\\\"b-image\\\" token=\\\"img-token\\\" width=\\\"640\\\" height=\\\"360\\\"/>\",\"reference_map\":{\"doc:spec\":\"docR\"}}}}"
          fi
        else
          printf '%s' "{\"ok\":true,\"data\":{\"document\":{\"document_id\":\"docR\",\"revision_id\":$synced_revision,\"content\":\"# Spec\\n\\nNew rule\\n\"}}}"
        fi
      elif [ "$format" = "xml" ]; then
        if [ "${FAKE_REVIEW_TORN_PAIR:-0}" = "1" ]; then
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":10,"content":"<h1 id=\"b-title\">Spec</h1>"}}}'
        elif [ "${FAKE_REVIEW_REMOTE_CHANGES_AFTER_FETCH:-0}" = "1" ] \
          && [ -n "${FAKE_REVIEW_STATE_DIR:-}" ] \
          && [ -e "$FAKE_REVIEW_STATE_DIR/late-revision" ]; then
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":10,"content":"<h1 id=\"b-title\">Spec</h1><p id=\"b-rule\">Late remote edit</p>"}}}'
        else
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":9,"content":"<h1 id=\"b-title\" align=\"left\">Spec</h1><p id=\"b-rule\" align=\"left\"><b>New rule</b></p><p id=\"b-repeat-1\">Repeat</p><p id=\"b-repeat-2\">Repeat</p><img id=\"b-image\" token=\"img-token\" width=\"640\" height=\"360\"/>","reference_map":{"doc:spec":"docR"}}}}'
        fi
      else
        if [ "${FAKE_REVIEW_REMOTE_CHANGES_AFTER_FETCH:-0}" = "1" ] \
          && [ -n "${FAKE_REVIEW_STATE_DIR:-}" ] \
          && [ -e "$FAKE_REVIEW_STATE_DIR/current-fetch-seen" ]; then
          : > "$FAKE_REVIEW_STATE_DIR/late-revision"
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":10,"content":"# Spec\n\nLate remote edit\n"}}}'
        elif [ "${FAKE_REVIEW_REMOTE_CHANGED:-0}" = "1" ]; then
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":10,"content":"# Spec\n\nLate remote edit\n"}}}'
        else
          if [ "${FAKE_REVIEW_REMOTE_CHANGES_AFTER_FETCH:-0}" = "1" ] \
            && [ -n "${FAKE_REVIEW_STATE_DIR:-}" ]; then
            : > "$FAKE_REVIEW_STATE_DIR/current-fetch-seen"
          fi
          printf '%s' '{"ok":true,"data":{"document":{"document_id":"docR","revision_id":9,"content":"# Spec\n\nNew rule\n"}}}'
        fi
      fi
      exit 0
    fi
    ;;
  drive)
    params=$(arg_after --params "$@")
    case "${2:-} ${3:-}" in
      "file.comments list")
        if [ -n "${FAKE_REVIEW_MUTATE_LOCAL_PATH:-}" ] \
          && [ ! -e "${FAKE_REVIEW_MUTATE_LOCAL_PATH}.mutated" ]; then
          printf '\nConcurrent local edit\n' >> "$FAKE_REVIEW_MUTATE_LOCAL_PATH"
          : > "${FAKE_REVIEW_MUTATE_LOCAL_PATH}.mutated"
        fi
        final_mode="${FAKE_REVIEW_FINAL_COMMENTS:-}"
        if [[ "$params" == *'"is_solved":true'* ]]; then
          solved_filter=true
        elif [[ "$params" == *'"is_solved":false'* ]]; then
          solved_filter=false
        else
          echo "comment list must pass is_solved explicitly" >&2
          exit 2
        fi
        if [ "${FAKE_REVIEW_DATA_NULL:-0}" = "1" ]; then
          printf '%s' '{"ok":true,"data":null}'
          exit 0
        fi
        if [ "${FAKE_REVIEW_MALFORMED_ITEM:-0}" = "1" ]; then
          printf '%s' '{"ok":true,"data":{"items":[null],"has_more":false}}'
          exit 0
        fi
        if [ "${FAKE_REVIEW_BAD_HAS_MORE:-0}" = "1" ]; then
          printf '%s' '{"ok":true,"data":{"items":[],"has_more":"false"}}'
          exit 0
        fi
        if [ "${FAKE_REVIEW_BAD_PAGE_TOKEN_TYPE:-0}" = "1" ]; then
          printf '%s' '{"ok":true,"data":{"items":[],"has_more":true,"page_token":42}}'
          exit 0
        fi
        if [ "${FAKE_REVIEW_TORN_COMMENT_SCAN_ONCE:-0}" = "1" ] \
          && [ "$solved_filter" = true ] \
          && [ -n "${FAKE_REVIEW_STATE_DIR:-}" ] \
          && [ ! -e "$FAKE_REVIEW_STATE_DIR/torn-comment-scan-seen" ]; then
          : > "$FAKE_REVIEW_STATE_DIR/torn-comment-scan-seen"
          printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c1","user_id":"ou1","create_time":100,"update_time":220,"is_solved":true,"solved_time":220,"solver_user_id":"ou1","is_whole":false,"quote":"New rule","has_more":false,"relation":{"content_deleted":false,"relation":"{\"22-docR\":{\"positionInfo\":{\"blockID\":\"b-rule\"}}}"},"reply_list":{"replies":[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}}]}}],"has_more":false}}'
          exit 0
        fi
        page_next=false
        if [[ "$params" == *'"page_token":"comments-next"'* ]]; then
          page_next=true
        fi
        if [ "${FAKE_REVIEW_CONTROLLED_ACTIONS:-0}" = "1" ]; then
          state_dir="${FAKE_REVIEW_STATE_DIR:-}"
          if [ -z "$state_dir" ]; then
            echo "FAKE_REVIEW_CONTROLLED_ACTIONS requires FAKE_REVIEW_STATE_DIR" >&2
            exit 2
          fi
          if [ "${FAKE_REVIEW_FINAL_READ_FAIL:-0}" = "1" ] \
            && [ -e "$state_dir/solved-c1" ]; then
            printf '%s' '{"ok":true,"data":null}'
            exit 0
          fi
          c1_solved=false
          if [ -e "$state_dir/solved-c1" ] && [ ! -e "$state_dir/reopened-c1" ]; then
            c1_solved=true
          fi
          c1_replies='[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}}]'
          c1_update=200
          if [ -e "$state_dir/reply-created-c1" ]; then
            if [ -e "$state_dir/pm-after-result-c1" ]; then
              c1_replies='[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}},{"reply_id":"r-result-c1","user_id":"ou-shared","create_time":260,"update_time":260,"content":{"elements":[{"type":"text_run","text_run":{"text":"Updated and verified"}}]}},{"reply_id":"r-pm-after","user_id":"ou1","create_time":280,"update_time":280,"content":{"elements":[{"type":"text_run","text_run":{"text":"Actually use B"}}]}}]'
              c1_update=280
            else
              c1_replies='[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}},{"reply_id":"r-result-c1","user_id":"ou-shared","create_time":260,"update_time":260,"content":{"elements":[{"type":"text_run","text_run":{"text":"Updated and verified"}}]}}]'
              c1_update=260
            fi
          elif [ -e "$state_dir/manual-reply-c1" ]; then
            c1_replies='[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}},{"reply_id":"r-pm-manual","user_id":"ou-shared","create_time":260,"update_time":260,"content":{"elements":[{"type":"text_run","text_run":{"text":"PM handled this"}}]}}]'
            c1_update=260
          fi
          if [ "$c1_solved" = true ]; then
            if [ "${FAKE_REVIEW_NO_SOLVED_TIME:-0}" = "1" ]; then
              c1_item="{\"comment_id\":\"c1\",\"user_id\":\"ou1\",\"create_time\":100,\"update_time\":270,\"is_solved\":true,\"solver_user_id\":\"ou-shared\",\"is_whole\":false,\"quote\":\"New rule\",\"has_more\":false,\"relation\":{\"content_deleted\":false,\"relation\":\"{\\\"22-docR\\\":{\\\"positionInfo\\\":{\\\"blockID\\\":\\\"b-rule\\\"}}}\"},\"reply_list\":{\"replies\":$c1_replies}}"
            else
              c1_item="{\"comment_id\":\"c1\",\"user_id\":\"ou1\",\"create_time\":100,\"update_time\":270,\"is_solved\":true,\"solved_time\":270,\"solver_user_id\":\"ou-shared\",\"is_whole\":false,\"quote\":\"New rule\",\"has_more\":false,\"relation\":{\"content_deleted\":false,\"relation\":\"{\\\"22-docR\\\":{\\\"positionInfo\\\":{\\\"blockID\\\":\\\"b-rule\\\"}}}\"},\"reply_list\":{\"replies\":$c1_replies}}"
            fi
          else
            c1_item="{\"comment_id\":\"c1\",\"user_id\":\"ou1\",\"create_time\":100,\"update_time\":$c1_update,\"is_solved\":false,\"is_whole\":false,\"quote\":\"New rule\",\"has_more\":false,\"relation\":{\"content_deleted\":false,\"relation\":\"{\\\"22-docR\\\":{\\\"positionInfo\\\":{\\\"blockID\\\":\\\"b-rule\\\"}}}\"},\"reply_list\":{\"replies\":$c1_replies}}"
          fi
          c2_solved=false
          if [ -e "$state_dir/solved-c2" ]; then
            c2_solved=true
          fi
          c2_replies='[{"reply_id":"r2","user_id":"ou2","create_time":120,"update_time":210,"content":{"elements":[{"type":"text_run","text_run":{"text":"Question"}}]}},{"reply_id":"r3","user_id":"ou3","create_time":130,"update_time":230,"content":{"elements":[{"type":"text_run","text_run":{"text":"Second reply"}}]}}]'
          c2_update=230
          if [ -e "$state_dir/reply-created-c2" ]; then
            c2_replies='[{"reply_id":"r2","user_id":"ou2","create_time":120,"update_time":210,"content":{"elements":[{"type":"text_run","text_run":{"text":"Question"}}]}},{"reply_id":"r3","user_id":"ou3","create_time":130,"update_time":230,"content":{"elements":[{"type":"text_run","text_run":{"text":"Second reply"}}]}},{"reply_id":"r-result-c2","user_id":"ou-shared","create_time":260,"update_time":260,"content":{"elements":[{"type":"text_run","text_run":{"text":"Updated and verified"}}]}}]'
            c2_update=260
          fi
          c2_item="{\"comment_id\":\"c2\",\"user_id\":\"ou2\",\"create_time\":120,\"update_time\":$c2_update,\"is_solved\":false,\"is_whole\":false,\"quote\":\"Repeat\",\"has_more\":false,\"reply_list\":{\"replies\":$c2_replies}}"
          if [ "${FAKE_REVIEW_NO_SOLVED_TIME:-0}" = "1" ]; then
            c2_solved_item="{\"comment_id\":\"c2\",\"user_id\":\"ou2\",\"create_time\":120,\"update_time\":280,\"is_solved\":true,\"solver_user_id\":\"ou-shared\",\"is_whole\":false,\"quote\":\"Repeat\",\"has_more\":false,\"reply_list\":{\"replies\":$c2_replies}}"
          else
            c2_solved_item="{\"comment_id\":\"c2\",\"user_id\":\"ou2\",\"create_time\":120,\"update_time\":280,\"is_solved\":true,\"solved_time\":280,\"solver_user_id\":\"ou-shared\",\"is_whole\":false,\"quote\":\"Repeat\",\"has_more\":false,\"reply_list\":{\"replies\":$c2_replies}}"
          fi
          if [ "$solved_filter" = true ]; then
            if [ "$c1_solved" = true ] && [ "$c2_solved" = true ]; then
              printf '%s' "{\"ok\":true,\"data\":{\"items\":[$c1_item,$c2_solved_item],\"has_more\":false}}"
            elif [ "$c1_solved" = true ]; then
              printf '%s' "{\"ok\":true,\"data\":{\"items\":[$c1_item],\"has_more\":false}}"
            elif [ "$c2_solved" = true ]; then
              printf '%s' "{\"ok\":true,\"data\":{\"items\":[$c2_solved_item],\"has_more\":false}}"
            else
              printf '%s' '{"ok":true,"data":{"items":[],"has_more":false}}'
            fi
          elif [ "$c1_solved" = true ] && [ "$c2_solved" = true ]; then
            printf '%s' '{"ok":true,"data":{"items":[],"has_more":false}}'
          elif [ "$c1_solved" = true ]; then
            printf '%s' "{\"ok\":true,\"data\":{\"items\":[$c2_item],\"has_more\":false}}"
          elif [ "$c2_solved" = true ]; then
            printf '%s' "{\"ok\":true,\"data\":{\"items\":[$c1_item],\"has_more\":false}}"
          elif [ "$page_next" = true ]; then
            printf '%s' "{\"ok\":true,\"data\":{\"items\":[$c2_item],\"has_more\":false}}"
          else
            printf '%s' "{\"ok\":true,\"data\":{\"items\":[$c1_item],\"has_more\":true,\"page_token\":\"comments-next\"}}"
          fi
          exit 0
        fi
        c1_solved=true
        if [ -n "${FAKE_REVIEW_STATE_DIR:-}" ] \
          && [ -e "$FAKE_REVIEW_STATE_DIR/reopened-c1" ]; then
          c1_solved=false
        fi
        if [ "${FAKE_REVIEW_COMMENT_CHANGED:-0}" = "1" ]; then
          if [ "$solved_filter" = true ]; then
            printf '%s' '{"ok":true,"data":{"items":[],"has_more":false}}'
          else
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c-late","user_id":"ou1","create_time":300,"update_time":300,"is_solved":false,"is_whole":true,"reply_list":{"replies":[{"reply_id":"r-late","user_id":"ou1","create_time":300,"update_time":300,"content":{"elements":[{"type":"text_run","text_run":{"text":"Late comment"}}]}}]}}],"has_more":false}}'
          fi
        elif [ "${FAKE_REVIEW_CREATE_ONLY:-0}" = "1" ]; then
          if [ "$solved_filter" = true ]; then
            printf '%s' '{"ok":true,"data":{"items":[],"has_more":false}}'
          else
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c-same-second","user_id":"ou1","create_time":150,"is_solved":false,"is_whole":true,"reply_list":{"replies":[{"reply_id":"r-same-second","user_id":"ou1","create_time":150,"content":{"elements":[{"type":"text_run","text_run":{"text":"Same second"}}]}}]}}],"has_more":false}}'
          fi
        elif [ "${FAKE_REVIEW_BAD_PAGE:-0}" = "1" ] && [ "$solved_filter" = false ]; then
          printf '%s' '{"ok":true,"data":{"items":[],"has_more":true}}'
        elif [ -z "$final_mode" ]; then
          if [ "$solved_filter" = true ]; then
            printf '%s' '{"ok":true,"data":{"items":[],"has_more":false}}'
          elif [ "$page_next" = true ]; then
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c2","user_id":"ou2","create_time":120,"update_time":210,"is_solved":false,"is_whole":false,"quote":"Repeat","has_more":true,"reply_list":{"replies":[]}}],"has_more":false}}'
          else
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c1","user_id":"ou1","create_time":100,"update_time":200,"is_solved":false,"is_whole":false,"quote":"New rule","has_more":false,"relation":{"content_deleted":false,"relation":"{\"22-docR\":{\"positionInfo\":{\"blockID\":\"b-rule\"}}}"},"reply_list":{"replies":[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}}]}}],"has_more":true,"page_token":"comments-next"}}'
          fi
        elif [ "$final_mode" = "solved-reply-pm" ]; then
          if [ "$solved_filter" = true ] && [ "$c1_solved" = true ]; then
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c1","user_id":"ou1","create_time":100,"update_time":270,"is_solved":true,"solved_time":270,"solver_user_id":"ou-agent","is_whole":false,"quote":"New rule","has_more":false,"relation":{"content_deleted":false,"relation":"{\"22-docR\":{\"positionInfo\":{\"blockID\":\"b-rule\"}}}"},"reply_list":{"replies":[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}},{"reply_id":"r-pm","user_id":"ou1","create_time":250,"update_time":250,"content":{"elements":[{"type":"text_run","text_run":{"text":"Actually use B"}}]}},{"reply_id":"r-result","user_id":"ou-agent","create_time":270,"update_time":270,"content":{"elements":[{"type":"text_run","text_run":{"text":"Updated and verified"}}]}}]}}],"has_more":false}}'
          elif [ "$solved_filter" = false ] && [ "$c1_solved" = false ] && [ "$page_next" = false ]; then
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c1","user_id":"ou1","create_time":100,"update_time":280,"is_solved":false,"is_whole":false,"quote":"New rule","has_more":false,"relation":{"content_deleted":false,"relation":"{\"22-docR\":{\"positionInfo\":{\"blockID\":\"b-rule\"}}}"},"reply_list":{"replies":[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}},{"reply_id":"r-pm","user_id":"ou1","create_time":250,"update_time":250,"content":{"elements":[{"type":"text_run","text_run":{"text":"Actually use B"}}]}},{"reply_id":"r-result","user_id":"ou-agent","create_time":270,"update_time":270,"content":{"elements":[{"type":"text_run","text_run":{"text":"Updated and verified"}}]}}]}}],"has_more":true,"page_token":"comments-next"}}'
          elif [ "$solved_filter" = false ] && { [ "$c1_solved" = true ] || [ "$page_next" = true ]; }; then
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c2","user_id":"ou2","create_time":120,"update_time":210,"is_solved":false,"is_whole":false,"quote":"Repeat","has_more":true,"reply_list":{"replies":[]}}],"has_more":false}}'
          else
            printf '%s' '{"ok":true,"data":{"items":[],"has_more":false}}'
          fi
        elif [ "$final_mode" = "deferred" ] || [ "$final_mode" = "reopened" ]; then
          if [ "$solved_filter" = true ]; then
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c1","user_id":"ou1","create_time":100,"update_time":240,"is_solved":true,"solved_time":240,"solver_user_id":"ou-agent","is_whole":false,"quote":"New rule","has_more":false,"relation":{"content_deleted":false,"relation":"{\"22-docR\":{\"positionInfo\":{\"blockID\":\"b-rule\"}}}"},"reply_list":{"replies":[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}}]}}],"has_more":false}}'
          else
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c2","user_id":"ou2","create_time":120,"update_time":210,"is_solved":false,"is_whole":false,"quote":"Repeat","has_more":true,"reply_list":{"replies":[]}}],"has_more":false}}'
          fi
        elif [ "$final_mode" = "solved-new" ] && [ "$solved_filter" = false ]; then
          printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c-late","user_id":"ou4","create_time":300,"update_time":300,"is_solved":false,"is_whole":true,"reply_list":{"replies":[{"reply_id":"r-late","user_id":"ou4","create_time":300,"update_time":300,"content":{"elements":[{"type":"text_run","text_run":{"text":"Late comment"}}]}}]}}],"has_more":false}}'
        elif [ "$solved_filter" = false ]; then
          printf '%s' '{"ok":true,"data":{"items":[],"has_more":false}}'
        elif [ "$page_next" = true ]; then
          if [ "$final_mode" = "solved-late" ]; then
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c2","user_id":"ou2","create_time":120,"update_time":241,"is_solved":true,"solved_time":241,"solver_user_id":"ou-agent","is_whole":false,"quote":"Repeat","has_more":true,"reply_list":{"replies":[]}},{"comment_id":"c-late","user_id":"ou4","create_time":300,"update_time":300,"is_solved":true,"solved_time":300,"solver_user_id":"ou4","is_whole":true,"reply_list":{"replies":[{"reply_id":"r-late","user_id":"ou4","create_time":300,"update_time":300,"content":{"elements":[{"type":"text_run","text_run":{"text":"Late comment"}}]}}]}}],"has_more":false}}'
          else
            printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c2","user_id":"ou2","create_time":120,"update_time":241,"is_solved":true,"solved_time":241,"solver_user_id":"ou-agent","is_whole":false,"quote":"Repeat","has_more":true,"reply_list":{"replies":[]}}],"has_more":false}}'
          fi
        elif [ "$final_mode" = "solved-reply" ]; then
          printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c1","user_id":"ou1","create_time":100,"update_time":260,"is_solved":true,"solved_time":260,"solver_user_id":"ou-agent","is_whole":false,"quote":"New rule","has_more":false,"relation":{"content_deleted":false,"relation":"{\"22-docR\":{\"positionInfo\":{\"blockID\":\"b-rule\"}}}"},"reply_list":{"replies":[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}},{"reply_id":"r-result","user_id":"ou-agent","create_time":260,"update_time":260,"content":{"elements":[{"type":"text_run","text_run":{"text":"Updated and verified"}}]}}]}}],"has_more":true,"page_token":"comments-next"}}'
        else
          printf '%s' '{"ok":true,"data":{"items":[{"comment_id":"c1","user_id":"ou1","create_time":100,"update_time":240,"is_solved":true,"solved_time":240,"solver_user_id":"ou-agent","is_whole":false,"quote":"New rule","has_more":false,"relation":{"content_deleted":false,"relation":"{\"22-docR\":{\"positionInfo\":{\"blockID\":\"b-rule\"}}}"},"reply_list":{"replies":[{"reply_id":"r1","user_id":"ou1","create_time":100,"update_time":200,"content":{"elements":[{"type":"text_run","text_run":{"text":"Use new rule"}}]}}]}}],"has_more":true,"page_token":"comments-next"}}'
        fi
        exit 0
        ;;
      "file.comments patch")
        comment_id="${params#*\"comment_id\":\"}"
        comment_id="${comment_id%%\"*}"
        if [ -z "$comment_id" ]; then
          echo "missing comment_id" >&2
          exit 2
        fi
        data=$(arg_after --data "$@")
        if [ "${FAKE_REVIEW_PATCH_FAIL:-0}" = "1" ]; then
          echo "comment patch failed" >&2
          exit 1
        fi
        solved=false
        if [[ "$data" == *'"is_solved":true'* ]]; then
          solved=true
          if [ -n "${FAKE_REVIEW_STATE_DIR:-}" ]; then
            : > "$FAKE_REVIEW_STATE_DIR/solved-$comment_id"
          fi
        elif [ -n "${FAKE_REVIEW_STATE_DIR:-}" ]; then
          : > "$FAKE_REVIEW_STATE_DIR/reopened-$comment_id"
        fi
        printf '%s' "{\"ok\":true,\"data\":{\"comment_id\":\"$comment_id\",\"is_solved\":$solved}}"
        exit 0
        ;;
      "file.comment.replys create")
        comment_id="${params#*\"comment_id\":\"}"
        comment_id="${comment_id%%\"*}"
        if [ "${FAKE_REVIEW_REPLY_CREATE_FAIL:-0}" = "1" ]; then
          echo "comment reply create failed" >&2
          exit 1
        fi
        if [ -n "${FAKE_REVIEW_STATE_DIR:-}" ]; then
          : > "$FAKE_REVIEW_STATE_DIR/reply-created-$comment_id"
        fi
        if [ "${FAKE_REVIEW_REPLY_CREATE_NO_CONTENT:-0}" = "1" ]; then
          printf '%s' "{\"ok\":true,\"data\":{\"reply_id\":\"r-result-$comment_id\",\"user_id\":\"ou-shared\",\"create_time\":260,\"update_time\":260}}"
        else
          printf '%s' "{\"ok\":true,\"data\":{\"reply_id\":\"r-result-$comment_id\",\"user_id\":\"ou-shared\",\"create_time\":260,\"update_time\":260,\"content\":{\"elements\":[{\"type\":\"text_run\",\"text_run\":{\"text\":\"Updated and verified\"}}]}}}"
        fi
        exit 0
        ;;
      "file.comment.replys list")
        if [[ "$params" == *'"page_token":"replies-next"'* ]]; then
          printf '%s' '{"ok":true,"data":{"items":[{"reply_id":"r3","user_id":"ou3","create_time":130,"update_time":230,"content":{"elements":[{"type":"text_run","text_run":{"text":"Second reply"}}]}}],"has_more":false}}'
        else
          printf '%s' '{"ok":true,"data":{"items":[{"reply_id":"r2","user_id":"ou2","create_time":120,"update_time":210,"content":{"elements":[{"type":"text_run","text_run":{"text":"Question"}}]}}],"has_more":true,"page_token":"replies-next"}}'
        fi
        exit 0
        ;;
    esac
    ;;
esac

echo "fake-lark-review-cli: unhandled $*" >&2
exit 2
