#!/usr/bin/env bash
# Smoke tests for scripts/_lib/lark_adapter.py.
# 用 tests/helpers/fake-lark-cli.sh 假装 lark-cli，验证 adapter cwd workaround
# + 子进程契约 + JSON shape。
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

FRAMEWORK_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SHIM_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/helpers/fake-lark-cli.sh" "$SHIM_DIR/lark-cli"
chmod +x "$SHIM_DIR/lark-cli"

cleanup() {
  rm -rf "$SHIM_DIR"
}
trap cleanup EXIT

# 所有子测试共用：PATH 把 SHIM_DIR 排在前 + PYTHONPATH 指向 scripts/
export PATH="$SHIM_DIR:$PATH"
export PYTHONPATH="$FRAMEWORK_ROOT/scripts"

# ---------------------------------------------------------------------------

test_version_parses() {
  start_test "version() 解析 fake CLI 输出"
  unset FAKE_LARK_VERSION
  out=$(python3 -c "from _lib.lark_adapter import version; print(version())")
  if [ "$out" = "(1, 0, 27)" ]; then
    pass_test
  else
    _fail "expected (1, 0, 27), got: $out"
  fi
}

test_version_too_old() {
  start_test "version() 拿到旧版本返回 tuple (caller 自判)"
  export FAKE_LARK_VERSION="lark-cli 1.0.10"
  out=$(python3 -c "from _lib.lark_adapter import version; print(version())")
  unset FAKE_LARK_VERSION
  if [ "$out" = "(1, 0, 10)" ]; then
    pass_test
  else
    _fail "expected (1, 0, 10), got: $out"
  fi
}

test_auth_status_ok() {
  start_test "auth_status() rc=0 → ok=True"
  unset FAKE_LARK_AUTH_STATUS_RC
  rc=$(python3 -c "from _lib.lark_adapter import auth_status; print(auth_status()[0])")
  if [ "$rc" = "True" ]; then
    pass_test
  else
    _fail "expected True, got: $rc"
  fi
}

test_auth_status_fail() {
  start_test "auth_status() rc=1 → ok=False"
  export FAKE_LARK_AUTH_STATUS_RC=1
  rc=$(python3 -c "from _lib.lark_adapter import auth_status; print(auth_status()[0])")
  unset FAKE_LARK_AUTH_STATUS_RC
  if [ "$rc" = "False" ]; then
    pass_test
  else
    _fail "expected False, got: $rc"
  fi
}

test_docs_create_cwd_workaround() {
  start_test "docs_create_from_markdown cwd=markdown.parent + @./<name>"
  local tmp; tmp=$(mktemp -d)
  local tmp_real; tmp_real=$(cd "$tmp" && pwd -P)
  echo "# Hello" > "$tmp/foo.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_create_from_markdown
out = docs_create_from_markdown(
    Path("$tmp/foo.md"),
    title="标题",
    target={"kind": "wiki", "token": "wikiNodeX"},
)
print("doc_id:", out["data"]["doc_id"])
PY
  if [ ! -s "$log" ]; then
    _fail "shim 没有写日志"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q "CWD: $tmp_real" "$log"; then
    _fail "expected CWD=$tmp_real in log; got: $(grep '^CWD:' "$log")"
    cat "$log" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q -- "--content @./foo.md" "$log"; then
    _fail "expected '--content @./foo.md' in ARGV; got: $(grep ARGV: "$log")"
    cat "$log" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q -- "--doc-format markdown" "$log"; then
    _fail "expected '--doc-format markdown' in ARGV"
    cat "$log" >&2
    rm -rf "$tmp"
    return
  fi
  if ! grep -q -- "--wiki-node wikiNodeX" "$log"; then
    _fail "expected '--wiki-node wikiNodeX' in ARGV"
    cat "$log" >&2
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_docs_create_folder_kind() {
  start_test "docs_create_from_markdown kind=folder 用 --folder-token"
  local tmp; tmp=$(mktemp -d)
  echo "# X" > "$tmp/x.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_create_from_markdown
docs_create_from_markdown(
    Path("$tmp/x.md"),
    title="t",
    target={"kind": "folder", "token": "folderT"},
)
PY
  if grep -q -- "--folder-token folderT" "$log"; then
    pass_test
  else
    _fail "expected '--folder-token folderT' in log"
    cat "$log" >&2
  fi
  rm -rf "$tmp"
}

test_docs_update_cwd_workaround() {
  start_test "docs_update_from_markdown cwd + @./<name>"
  local tmp; tmp=$(mktemp -d)
  local tmp_real; tmp_real=$(cd "$tmp" && pwd -P)
  echo "# Hi" > "$tmp/bar.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_update_from_markdown
docs_update_from_markdown(Path("$tmp/bar.md"), doc_id="docY", revision_id=42)
PY
  if grep -q "CWD: $tmp_real" "$log" && grep -q -- "--content @./bar.md" "$log" \
     && grep -q -- "--doc docY" "$log" && grep -q -- "--command overwrite" "$log" \
     && grep -q -- "--doc-format markdown" "$log" \
     && grep -q -- "--revision-id 42" "$log"; then
    pass_test
  else
    _fail "shim log 缺关键参数"
    cat "$log" >&2
  fi
  rm -rf "$tmp"
}

test_docs_update_rejects_partial_success() {
  start_test "docs_update_from_markdown 拒绝 partial_success"
  local tmp; tmp=$(mktemp -d)
  echo "# Partial" > "$tmp/partial.md"
  export FAKE_LARK_DOCS_UPDATE_OUT='{"ok":true,"data":{"document":{"document_id":"docY","revision_id":43},"result":"partial_success","updated_blocks_count":1,"warnings":["one block failed"]}}'
  out=$(python3 - "$tmp/partial.md" <<'PY' 2>&1
import sys
from pathlib import Path
from _lib.lark_adapter import LarkAdapterError, docs_update_from_markdown
try:
    docs_update_from_markdown(Path(sys.argv[1]), doc_id="docY", revision_id=42)
    print("OOPS")
except LarkAdapterError as exc:
    print(f"OK: {exc.kind}")
PY
)
  unset FAKE_LARK_DOCS_UPDATE_OUT
  rm -rf "$tmp"
  if [ "$out" = "OK: incomplete_update" ]; then
    pass_test
  else
    _fail "expected incomplete_update, got: $out"
  fi
}

test_markdown_must_be_path() {
  start_test "markdown 参数禁止字符串 → LarkAdapterError"
  out=$(python3 - <<'PY' 2>&1
from _lib.lark_adapter import docs_create_from_markdown, LarkAdapterError
try:
    docs_create_from_markdown("@./x.md", title="t", target={"kind":"wiki","token":"x"})  # type: ignore
    print("OOPS")
except LarkAdapterError as e:
    print(f"OK: {e.kind}")
PY
)
  if [ "$out" = "OK: validation" ]; then
    pass_test
  else
    _fail "expected OK: validation, got: $out"
  fi
}

test_markdown_missing_file_rejected() {
  start_test "markdown 文件不存在 → LarkAdapterError(validation)"
  out=$(python3 - <<'PY' 2>&1
from pathlib import Path
from _lib.lark_adapter import docs_create_from_markdown, LarkAdapterError
try:
    docs_create_from_markdown(Path("/nonexistent/x.md"), title="t",
                              target={"kind":"wiki","token":"x"})
    print("OOPS")
except LarkAdapterError as e:
    print(f"OK: {e.kind}")
PY
)
  if [ "$out" = "OK: validation" ]; then
    pass_test
  else
    _fail "expected OK: validation, got: $out"
  fi
}

test_api_json_passthrough() {
  start_test "api_json() 透传 JSON dict"
  export FAKE_LARK_API_OUT='{"data":{"items":[{"id":"b1"}],"page_token":null}}'
  out=$(python3 - <<'PY'
from _lib.lark_adapter import api_json
resp = api_json("GET", "/open-apis/docx/v1/documents/D/blocks")
print(resp["data"]["items"][0]["id"])
PY
)
  unset FAKE_LARK_API_OUT
  if [ "$out" = "b1" ]; then
    pass_test
  else
    _fail "expected b1, got: $out"
  fi
}

test_docs_fetch_im_markdown_requires_1_0_58() {
  start_test "docs_fetch(im-markdown) 使用格式级最低版本"
  export FAKE_LARK_VERSION="lark-cli 1.0.57"
  out=$(python3 - <<'PY' 2>&1
from _lib.lark_adapter import LarkAdapterError, docs_fetch
try:
    docs_fetch("docX", doc_format="im-markdown")
    print("OOPS")
except LarkAdapterError as exc:
    print(f"{exc.kind}: {exc.detail}")
PY
)
  unset FAKE_LARK_VERSION
  if [ "$out" = "validation: docs_fetch(im-markdown) 需要 lark-cli >= 1.0.58，当前为 1.0.57" ]; then
    pass_test
  else
    _fail "expected im-markdown version gate, got: $out"
  fi
}

test_drive_comment_set_solved_uses_patch_contract() {
  start_test "drive_comment_set_solved() 使用 Docx comment patch 合同"
  local tmp; tmp=$(mktemp -d)
  local log="$tmp/calls.log"
  out=$(FAKE_LARK_LOG="$log" python3 - <<'PY'
from _lib.lark_adapter import drive_comment_set_solved
payload = drive_comment_set_solved("docX", "c1", is_solved=False)
print(payload["data"]["is_solved"])
PY
)
  if [ "$out" = "False" ] \
    && grep -q 'ARGV: drive file.comments patch' "$log" \
    && grep -q -- '--params {"comment_id":"c1","file_token":"docX","file_type":"docx"}' "$log" \
    && grep -q -- '--data {"is_solved":false}' "$log"; then
    pass_test
  else
    _fail "comment patch contract mismatch: out=$out log=$(cat "$log")"
  fi
  rm -rf "$tmp"
}

test_drive_comment_reply_create_uses_reply_contract() {
  start_test "drive_comment_reply_create() 使用 Docx comment reply create 合同"
  local tmp; tmp=$(mktemp -d)
  local log="$tmp/calls.log"
  out=$(FAKE_LARK_LOG="$log" python3 - <<'PY'
from _lib.lark_adapter import drive_comment_reply_create
payload = drive_comment_reply_create("docX", "c1", "Updated and verified")
print(payload["data"]["reply_id"], payload["data"]["user_id"])
PY
)
  if [ "$out" = "r-result ou-agent" ] \
    && grep -q 'ARGV: drive file.comment.replys create' "$log" \
    && grep -q -- '--params {"file_token":"docX","file_type":"docx","comment_id":"c1","user_id_type":"open_id"}' "$log" \
    && grep -q -- '--data {"content":{"elements":\[{"type":"text_run","text_run":{"text":"Updated and verified"}}\]}}' "$log"; then
    pass_test
  else
    _fail "comment reply create contract mismatch: out=$out log=$(cat "$log")"
  fi
  rm -rf "$tmp"
}

test_drive_comments_page_passes_explicit_solved_filter() {
  start_test "drive_comments_page() 不依赖 is_solved 默认值"
  local tmp; tmp=$(mktemp -d)
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<'PY'
from _lib.lark_adapter import drive_comments_page
drive_comments_page("docX", is_solved=False)
drive_comments_page("docX", is_solved=True)
PY
  if grep -q -- '--params {"file_token":"docX","file_type":"docx","page_size":100,"user_id_type":"open_id","is_solved":false,"need_relation":true}' "$log" \
    && grep -q -- '--params {"file_token":"docX","file_type":"docx","page_size":100,"user_id_type":"open_id","is_solved":true,"need_relation":true}' "$log"; then
    pass_test
  else
    _fail "comment list must pass both solved filters explicitly: $(cat "$log")"
  fi
  rm -rf "$tmp"
}

test_subprocess_failure_raises() {
  start_test "lark-cli 非 0 退出 → LarkAdapterError(subprocess)"
  export FAKE_LARK_DOCS_UPDATE_RC=2
  local tmp; tmp=$(mktemp -d)
  echo "# Z" > "$tmp/z.md"
  out=$(python3 - <<PY 2>&1
from pathlib import Path
from _lib.lark_adapter import docs_update_from_markdown, LarkAdapterError
try:
    docs_update_from_markdown(Path("$tmp/z.md"), doc_id="docZ")
    print("OOPS")
except LarkAdapterError as e:
    print(f"OK: {e.kind}")
PY
)
  unset FAKE_LARK_DOCS_UPDATE_RC
  rm -rf "$tmp"
  if [ "$out" = "OK: subprocess" ]; then
    pass_test
  else
    _fail "expected OK: subprocess, got: $out"
  fi
}

test_missing_cli_in_path() {
  start_test "lark-cli 不在 PATH → LarkAdapterError(missing_cli)"
  out=$(PATH="/usr/bin:/bin" python3 - <<'PY' 2>&1
from _lib.lark_adapter import version, LarkAdapterError
try:
    version()
    print("OOPS")
except LarkAdapterError as e:
    print(f"OK: {e.kind}")
PY
)
  if [ "$out" = "OK: missing_cli" ]; then
    pass_test
  else
    _fail "expected OK: missing_cli, got: $out"
  fi
}

test_doctor_subcommand_happy() {
  start_test "python -m _lib.lark_adapter doctor 全过"
  out=$(python3 -m _lib.lark_adapter doctor 2>&1)
  rc=$?
  if [ $rc -eq 0 ] && echo "$out" | grep -q "version       : OK" \
     && echo "$out" | grep -q "auth_status   : OK"; then
    pass_test
  else
    _fail "expected doctor 0 + 'OK', got rc=$rc out: $out"
  fi
}

test_parse_frontmatter() {
  start_test "parse_frontmatter() 拆分 frontmatter 与正文"
  out=$(python3 - <<'PY'
from _lib.lark_adapter import parse_frontmatter
fm, body = parse_frontmatter("---\nlark_doc_id: docX\nfoo: bar\n---\n# 正文\n内容")
print(fm.get("lark_doc_id") == "docX", fm.get("foo") == "bar", body == "# 正文\n内容")
PY
)
  if [ "$out" = "True True True" ]; then
    pass_test
  else
    _fail "expected 'True True True', got: $out"
  fi
}

test_parse_frontmatter_none() {
  start_test "parse_frontmatter() 无 frontmatter → ({}, 原文)"
  out=$(python3 - <<'PY'
from _lib.lark_adapter import parse_frontmatter
fm, body = parse_frontmatter("# 标题\n正文")
print(len(fm), body == "# 标题\n正文")
PY
)
  if [ "$out" = "0 True" ]; then
    pass_test
  else
    _fail "expected '0 True', got: $out"
  fi
}

test_write_frontmatter_preserves_unknown_yaml() {
  start_test "write_frontmatter 只补丁标量并保留嵌套 YAML / 注释 / 正文"
  local tmp; tmp=$(mktemp -d)
  cat > "$tmp/preserve.md" <<'MD'
---
# keep this comment
owners:
  - alice
metadata:
  team: platform
summary: |
  line one
  line two
lark_doc_id: docOld
---

# Body

Keep me.
MD
  out=$(python3 - "$tmp/preserve.md" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import parse_frontmatter, write_frontmatter
path = Path(sys.argv[1])
raw = path.read_text(encoding="utf-8")
fm, body = parse_frontmatter(raw)
fm["lark_published_revision_id"] = 12
fm["lark_published_source_hash"] = "abc123"
write_frontmatter(path, fm, body)
print("OK")
PY
)
  if [ "$out" != "OK" ] \
    || ! grep -q '^# keep this comment$' "$tmp/preserve.md" \
    || ! grep -q '^  - alice$' "$tmp/preserve.md" \
    || ! grep -q '^  team: platform$' "$tmp/preserve.md" \
    || ! grep -q '^  line two$' "$tmp/preserve.md" \
    || ! grep -q '^lark_published_revision_id: 12$' "$tmp/preserve.md" \
    || ! grep -q '^Keep me\.$' "$tmp/preserve.md"; then
    _fail "frontmatter 补丁破坏了未知 YAML 或正文: $(cat "$tmp/preserve.md")"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_replace_markdown_body_preserves_frontmatter() {
  start_test "replace_markdown_body 原子替换正文并逐字保留 frontmatter"
  local tmp; tmp=$(mktemp -d)
  cat > "$tmp/body.md" <<'MD'
---
# keep comment
owners:
  - alice
lark_doc_id: docOld
---

# Old
MD
  out=$(python3 - "$tmp/body.md" <<'PY'
import sys
from pathlib import Path
from _lib.lark_adapter import replace_markdown_body
path = Path(sys.argv[1])
raw = path.read_text(encoding="utf-8")
replace_markdown_body(path, "# New\n", expected_text=raw)
print("OK")
PY
)
  if [ "$out" != "OK" ] \
    || ! grep -q '^# keep comment$' "$tmp/body.md" \
    || ! grep -q '^  - alice$' "$tmp/body.md" \
    || ! grep -q '^lark_doc_id: docOld$' "$tmp/body.md" \
    || ! grep -q '^# New$' "$tmp/body.md" \
    || grep -q '^# Old$' "$tmp/body.md"; then
    _fail "正文替换破坏了 frontmatter 或保留了旧正文: $(cat "$tmp/body.md")"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_docs_create_strips_frontmatter() {
  start_test "docs_create_from_markdown 发送前剥离 frontmatter"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '---' 'lark_doc_id: docOld' 'title: T' '---' '# 真正文' '正文内容' \
    > "$tmp/fm.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_create_from_markdown
docs_create_from_markdown(Path("$tmp/fm.md"), title="t",
                          target={"kind": "wiki", "token": "w"})
PY
  # lark-cli 实际收到的 markdown 首行必须是正文，不能是 --- 或 frontmatter key
  if ! grep -q "MARKDOWN_HEAD: # 真正文" "$log"; then
    _fail "frontmatter 未剥离；got: $(grep MARKDOWN_HEAD "$log")"
    cat "$log" >&2
    rm -rf "$tmp"
    return
  fi
  if grep -q "MARKDOWN_HEAD: ---" "$log" || grep -q "MARKDOWN_HEAD: lark_doc_id" "$log"; then
    _fail "frontmatter 泄漏进正文；got: $(grep MARKDOWN_HEAD "$log")"
    rm -rf "$tmp"
    return
  fi
  # 临时文件用完即清理，原文件不动
  if ls "$tmp" | grep -q 'lark-'; then
    _fail "剥离用的临时文件未清理：$(ls "$tmp")"
    rm -rf "$tmp"
    return
  fi
  if ! grep -q '^lark_doc_id: docOld' "$tmp/fm.md"; then
    _fail "原文件 frontmatter 被改动"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_docs_update_strips_frontmatter() {
  start_test "docs_update_from_markdown 发送前剥离 frontmatter（覆盖发布场景）"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '---' 'lark_doc_id: docOld' '---' '# 覆盖正文' '内容' > "$tmp/up.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_update_from_markdown
docs_update_from_markdown(Path("$tmp/up.md"), doc_id="docOld")
PY
  if grep -q "MARKDOWN_HEAD: # 覆盖正文" "$log" \
     && ! grep -q "MARKDOWN_HEAD: ---" "$log"; then
    pass_test
  else
    _fail "覆盖发布未剥离 frontmatter；got: $(grep MARKDOWN_HEAD "$log")"
    cat "$log" >&2
  fi
  rm -rf "$tmp"
}

test_docs_create_no_frontmatter_uses_original() {
  start_test "无 frontmatter 时直接发原文件（不产生临时文件）"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '# 无 fm' '正文' > "$tmp/plain.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_create_from_markdown
docs_create_from_markdown(Path("$tmp/plain.md"), title="t",
                          target={"kind": "wiki", "token": "w"})
PY
  if grep -q -- "--content @./plain.md" "$log" && ! ls "$tmp" | grep -q 'lark-'; then
    pass_test
  else
    _fail "无 frontmatter 应直接用原文件；argv: $(grep ARGV "$log")；目录: $(ls "$tmp")"
  fi
  rm -rf "$tmp"
}

# Run all
test_version_parses
test_version_too_old
test_auth_status_ok
test_auth_status_fail
test_docs_create_cwd_workaround
test_docs_create_folder_kind
test_docs_update_cwd_workaround
test_docs_update_rejects_partial_success
test_markdown_must_be_path
test_markdown_missing_file_rejected
test_api_json_passthrough
test_docs_fetch_im_markdown_requires_1_0_58
test_drive_comment_set_solved_uses_patch_contract
test_drive_comment_reply_create_uses_reply_contract
test_drive_comments_page_passes_explicit_solved_filter
test_subprocess_failure_raises
test_missing_cli_in_path
test_doctor_subcommand_happy
test_parse_frontmatter
test_parse_frontmatter_none
test_write_frontmatter_preserves_unknown_yaml
test_replace_markdown_body_preserves_frontmatter
test_docs_create_strips_frontmatter
test_docs_update_strips_frontmatter
test_docs_create_no_frontmatter_uses_original

report_results "lark-adapter"
