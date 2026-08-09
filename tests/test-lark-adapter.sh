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
  start_test "docs_create_from_markdown 固定 markdown.parent cwd + stdin 正文"
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
  if ! grep -q -- '--content -' "$log" \
    || ! grep -q 'STDIN_HEAD: # Hello' "$log"; then
    _fail "expected controlled stdin content; got: $(cat "$log")"
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
  start_test "docs_update_from_markdown 固定 cwd + stdin 正文"
  local tmp; tmp=$(mktemp -d)
  local tmp_real; tmp_real=$(cd "$tmp" && pwd -P)
  echo "# Hi" > "$tmp/bar.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_update_from_markdown
docs_update_from_markdown(Path("$tmp/bar.md"), doc_id="docY", revision_id=42)
PY
  if grep -q "CWD: $tmp_real" "$log" \
     && grep -q -- '--content -' "$log" \
     && grep -q 'STDIN_HEAD: # Hi' "$log" \
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

test_docs_update_rejects_all_unverifiable_results() {
  start_test "docs_update_from_markdown 将已发起更新后的不可验证结果统一标为 incomplete"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '# Update' 'private-update-body' > "$tmp/update.md"
  out=$(python3 - "$tmp/update.md" <<'PY' 2>&1
import os
import sys
from pathlib import Path

from _lib.lark_adapter import LarkAdapterError, docs_update_from_markdown

markdown = Path(sys.argv[1])
cases = (
    {"FAKE_LARK_DOCS_UPDATE_EMPTY": "1"},
    {"FAKE_LARK_DOCS_UPDATE_OUT": "private-invalid-json-output"},
    {"FAKE_LARK_DOCS_UPDATE_OUT": '["private-non-object-output"]'},
    {"FAKE_LARK_DOCS_UPDATE_OUT": '{"ok":true,"data":{}}'},
)
for environment in cases:
    os.environ.update(environment)
    try:
        docs_update_from_markdown(markdown, doc_id="doc-update", revision_id=8)
        raise AssertionError(f"unverifiable update result was accepted: {environment}")
    except LarkAdapterError as exc:
        assert exc.kind == "incomplete_update", (environment, exc.kind, str(exc))
        assert "private-" not in str(exc), (environment, str(exc))
    finally:
        for key in environment:
            os.environ.pop(key, None)
print("OK")
PY
  )
  rm -rf "$tmp"
  if [ "$out" = "OK" ]; then
    pass_test
  else
    _fail "unverifiable update result did not fail closed: $out"
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

test_json_entrypoints_reject_failure_envelopes() {
  start_test "create/update/fetch/comments/api 统一拒绝失败 JSON envelope"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '# Secret' 'private-markdown-body' > "$tmp/secret.md"
  out=$(python3 - "$tmp/secret.md" <<'PY' 2>&1
import json
import os
import sys
from pathlib import Path

from _lib.lark_adapter import (
    LarkAdapterError,
    api_json,
    docs_create_from_markdown,
    docs_fetch,
    docs_update_from_markdown,
    drive_comments_page,
)

markdown = Path(sys.argv[1])
entrypoints = (
    (
        "FAKE_LARK_DOCS_CREATE_OUT",
        lambda: docs_create_from_markdown(
            markdown,
            title="secret",
            target={"kind": "wiki", "token": "wiki-secret"},
        ),
        "subprocess",
        True,
    ),
    (
        "FAKE_LARK_DOCS_UPDATE_OUT",
        lambda: docs_update_from_markdown(markdown, doc_id="doc-secret"),
        "incomplete_update",
        True,
    ),
    ("FAKE_LARK_DOCS_FETCH_OUT", lambda: docs_fetch("doc-secret"), "subprocess", False),
    (
        "FAKE_LARK_COMMENTS_OUT",
        lambda: drive_comments_page("doc-secret"),
        "subprocess",
        False,
    ),
    (
        "FAKE_LARK_API_OUT",
        lambda: api_json("GET", "/open-apis/test"),
        "subprocess",
        False,
    ),
)
envelopes = (
    {"ok": False},
    {"success": False},
    {"code": 90001},
)
for variable, command, expected_kind, redact in entrypoints:
    for envelope in envelopes:
        payload = {
            **envelope,
            "message": "private-envelope-output",
            "data": {"result": "success"},
        }
        os.environ[variable] = json.dumps(payload)
        try:
            command()
            raise AssertionError(f"failure envelope was accepted: {variable} {envelope}")
        except LarkAdapterError as exc:
            assert exc.kind == expected_kind, (variable, envelope, exc.kind, str(exc))
            if redact:
                assert "private-" not in str(exc), (variable, envelope, str(exc))
    os.environ.pop(variable, None)

os.environ["FAKE_LARK_API_OUT"] = "[]"
try:
    api_json("GET", "/open-apis/test")
    raise AssertionError("api_json accepted a non-object JSON response")
except LarkAdapterError as exc:
    assert exc.kind == "non_json", (exc.kind, str(exc))
finally:
    os.environ.pop("FAKE_LARK_API_OUT", None)
print("OK")
PY
  )
  rm -rf "$tmp"
  if [ "$out" = "OK" ]; then
    pass_test
  else
    _fail "JSON failure envelope was not rejected consistently: $out"
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
  start_test "docs update 已发起后非 0 退出 → LarkAdapterError(incomplete_update)"
  export FAKE_LARK_DOCS_UPDATE_RC=2
  export FAKE_LARK_ECHO_STDIN_ON_ERROR=1
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '# Z' 'private-body-must-not-appear-in-error' > "$tmp/z.md"
  out=$(python3 - <<PY 2>&1
from pathlib import Path
from _lib.lark_adapter import docs_update_from_markdown, LarkAdapterError
try:
    docs_update_from_markdown(Path("$tmp/z.md"), doc_id="docZ")
    print("OOPS")
except LarkAdapterError as e:
    assert "private-body-must-not-appear-in-error" not in str(e), str(e)
    assert "子进程输出已隐藏" in str(e), str(e)
    print(f"OK: {e.kind}")
PY
)
  unset FAKE_LARK_DOCS_UPDATE_RC FAKE_LARK_ECHO_STDIN_ON_ERROR
  rm -rf "$tmp"
  if [ "$out" = "OK: incomplete_update" ]; then
    pass_test
  else
    _fail "expected OK: incomplete_update, got: $out"
  fi
}

test_successful_markdown_command_invalid_output_is_redacted() {
  start_test "lark-cli 成功退出但回显 stdin 时错误不泄漏正文"
  export FAKE_LARK_ECHO_STDIN_AS_DOCS_OUTPUT=1
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '# Secret' 'private-success-body-must-not-appear-in-error' > "$tmp/secret.md"
  out=$(python3 - "$tmp/secret.md" <<'PY' 2>&1
import sys
from pathlib import Path
from _lib.lark_adapter import (
    LarkAdapterError,
    docs_create_from_markdown,
    docs_update_from_markdown,
)

markdown = Path(sys.argv[1])
commands = (
    ("non_json", lambda: docs_create_from_markdown(
        markdown,
        title="secret",
        target={"kind": "wiki", "token": "wiki-secret"},
    )),
    ("incomplete_update", lambda: docs_update_from_markdown(markdown, doc_id="doc-secret")),
)
for expected_kind, command in commands:
    try:
        command()
        raise AssertionError("markdown command unexpectedly accepted echoed stdin")
    except LarkAdapterError as exc:
        assert exc.kind == expected_kind, str(exc)
        assert "private-success-body-must-not-appear-in-error" not in str(exc), str(exc)
        assert "子进程输出已隐藏" in str(exc), str(exc)
print("OK")
PY
  )
  unset FAKE_LARK_ECHO_STDIN_AS_DOCS_OUTPUT
  rm -rf "$tmp"
  if [ "$out" = "OK" ]; then
    pass_test
  else
    _fail "successful stdin echo was not redacted: $out"
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

test_write_frontmatter_rejects_line_break_injection() {
  start_test "write_frontmatter 拒绝 CR、Unicode 换行和非法 key 注入"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '---' 'lark_doc_id: docSafe' '---' '# Body' > "$tmp/safe.md"
  out=$(python3 - "$tmp/safe.md" <<'PY' 2>&1
import sys
from pathlib import Path

from _lib.lark_adapter import LarkAdapterError, parse_frontmatter, write_frontmatter

path = Path(sys.argv[1])
original = path.read_text(encoding="utf-8")
frontmatter, body = parse_frontmatter(original)
cases = (
    ("lark_reviewed_at", "ok\rlark_published_revision_id: 999"),
    ("lark_reviewed_at", "ok\u2028lark_published_revision_id: 999"),
    ("valid: injected", "value"),
)
for key, value in cases:
    candidate = dict(frontmatter)
    candidate[key] = value
    try:
        write_frontmatter(path, candidate, body, expected_text=original)
    except LarkAdapterError as exc:
        assert exc.kind == "validation", (key, exc.kind, str(exc))
    else:
        raise AssertionError(f"unsafe frontmatter scalar accepted: {key!r} {value!r}")
    assert path.read_text(encoding="utf-8") == original
print("OK")
PY
  )
  if [ "$out" = "OK" ]; then
    pass_test
  else
    _fail "frontmatter line-break injection was not rejected: $out"
  fi
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

test_path_apis_and_bound_markdown_accept_parent_alias() {
  start_test "普通 Path API 与 BoundMarkdown 接受合法父目录 alias"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/real"
  ln -s "$tmp/real" "$tmp/alias"
  cat > "$tmp/real/doc.md" <<'MD'
---
lark_doc_id: docAlias
---
# Old
MD
  local log="$tmp/calls.log"
  out=$(FAKE_LARK_LOG="$log" python3 - "$tmp/alias/doc.md" "$tmp/real" <<'PY' 2>&1
import sys
from pathlib import Path

from _lib.lark_adapter import (
    bind_markdown,
    docs_create_from_markdown,
    parse_frontmatter,
    replace_markdown_body,
    write_frontmatter,
)

path = Path(sys.argv[1])
real_parent = Path(sys.argv[2]).resolve()
raw = path.read_text(encoding="utf-8")
frontmatter, body = parse_frontmatter(raw)
frontmatter["lark_published_revision_id"] = 3
write_frontmatter(path, frontmatter, body, expected_text=raw)

written = path.read_text(encoding="utf-8")
replace_markdown_body(path, "# New\n", expected_text=written)
with bind_markdown(path) as markdown:
    assert markdown.path.parent == real_parent, markdown.path
    payload = docs_create_from_markdown(
        markdown,
        title="alias",
        target={"kind": "wiki", "token": "wiki-alias"},
    )
assert payload["data"]["doc_id"] == "docX1", payload
assert "lark_published_revision_id: 3" in path.read_text(encoding="utf-8")
assert path.read_text(encoding="utf-8").endswith("# New\n")
print("OK")
PY
  )
  if [ "$out" != "OK" ] \
    || ! grep -q 'STDIN_HEAD: # New' "$log"; then
    _fail "合法父目录 alias 被误拒或写入越界: out=$out log=$(cat "$log")"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_replace_markdown_body_rejects_rebound_parent_symlink() {
  start_test "replace_markdown_body 安全模式拒绝最终写入前的父目录 symlink 重绑"
  local tmp; tmp=$(mktemp -d)
  mkdir -p "$tmp/original" "$tmp/alternate"
  printf '%s\n' '# Old' > "$tmp/original/body.md"
  printf '%s\n' '# Old' > "$tmp/alternate/body.md"
  local canonical
  canonical=$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' \
    "$tmp/original/body.md")
  rm "$tmp/original/body.md"
  rmdir "$tmp/original"
  ln -s "$tmp/alternate" "$tmp/original"

  local out rc
  out=$(python3 - "$canonical" <<'PY' 2>&1
import sys
from pathlib import Path
from _lib.lark_adapter import replace_markdown_body

path = Path(sys.argv[1])
replace_markdown_body(
    path,
    "# New\n",
    expected_text="# Old\n",
    require_canonical_path=True,
)
PY
  )
  rc=$?
  if [ "$rc" -eq 0 ] || ! echo "$out" | grep -q 'symlink' \
    || ! grep -q '^# Old$' "$tmp/alternate/body.md" \
    || grep -q '^# New$' "$tmp/alternate/body.md"; then
    _fail "rebound parent symlink reached the alternate target: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_replace_markdown_body_rejects_symlink_and_fifo_without_blocking() {
  start_test "replace_markdown_body 初读拒绝 symlink 和 FIFO 且不阻塞"
  local tmp; tmp=$(mktemp -d)
  local out rc

  out=$(python3 - "$tmp" <<'PY' 2>&1
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
target = root / "target.md"
target.write_text("# Target\n", encoding="utf-8")
symlink = root / "symlink.md"
symlink.symlink_to(target)
fifo = root / "fifo.md"
os.mkfifo(fifo)

program = r'''
import sys
from pathlib import Path
from _lib.lark_adapter import LarkAdapterError, replace_markdown_body

try:
    replace_markdown_body(
        Path(sys.argv[1]),
        "# New\n",
        require_canonical_path=True,
    )
except LarkAdapterError as exc:
    assert exc.kind == "validation", (exc.kind, str(exc))
else:
    raise AssertionError("unsafe target unexpectedly accepted")
'''

for path in (symlink, fifo):
    try:
        result = subprocess.run(
            [sys.executable, "-c", program, str(path)],
            capture_output=True,
            text=True,
            timeout=2,
            env=os.environ.copy(),
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"initial read blocked on {path.name}") from exc
    assert result.returncode == 0, (path.name, result.stdout, result.stderr)

assert target.read_text(encoding="utf-8") == "# Target\n"
assert symlink.is_symlink()
assert fifo.exists()
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "不安全目标初读未快速失败: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_docs_send_rejects_symlink_and_fifo_without_blocking() {
  start_test "docs markdown 入口拒绝 symlink 和 FIFO 且不阻塞"
  local tmp; tmp=$(mktemp -d)
  local out rc

  out=$(python3 - "$tmp" <<'PY' 2>&1
import os
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
target = root / "target.md"
target.write_text("# Target\n", encoding="utf-8")
symlink = root / "symlink.md"
symlink.symlink_to(target)
fifo = root / "fifo.md"
os.mkfifo(fifo)

program = r'''
import sys
from pathlib import Path
from _lib.lark_adapter import LarkAdapterError, docs_create_from_markdown

try:
    docs_create_from_markdown(
        Path(sys.argv[1]),
        title="t",
        target={"kind": "wiki", "token": "w"},
    )
except LarkAdapterError as exc:
    assert exc.kind == "validation", (exc.kind, str(exc))
else:
    raise AssertionError("unsafe markdown unexpectedly accepted")
'''

for path in (symlink, fifo):
    try:
        result = subprocess.run(
            [sys.executable, "-c", program, str(path)],
            capture_output=True,
            text=True,
            timeout=2,
            env=os.environ.copy(),
        )
    except subprocess.TimeoutExpired as exc:
        raise AssertionError(f"docs markdown validation blocked on {path.name}") from exc
    assert result.returncode == 0, (path.name, result.stdout, result.stderr)

assert target.read_text(encoding="utf-8") == "# Target\n"
assert symlink.is_symlink()
assert fifo.exists()
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "docs markdown unsafe entry did not fail quickly: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_docs_send_entry_swap_and_parent_rebind_uses_stdin() {
  start_test "docs 发送期间同名换 inode + 父目录改向仍只发送绑定正文"
  local tmp; tmp=$(mktemp -d)
  local out rc

  out=$(FAKE_LARK_LOG="$tmp/calls.log" python3 - "$tmp" <<'PY' 2>&1
import os
import sys
from pathlib import Path

from _lib import lark_adapter

root = Path(sys.argv[1]).resolve()
parent = root / "docs"
held_parent = root / "docs-held"
outside = root / "outside"
parent.mkdir()
outside.mkdir()
markdown = parent / "spec.md"
markdown.write_text(
    "---\nlark_doc_id: docInside\n---\n# Inside\ninside body\n",
    encoding="utf-8",
)
(outside / "spec.md").write_text("# Outside secret\n", encoding="utf-8")
(outside / "sentinel.txt").write_text("outside-sentinel\n", encoding="utf-8")

original_run = lark_adapter._run


def racing_run(cmd, **kwargs):
    assert kwargs["input_data"] == "# Inside\ninside body\n", kwargs
    bound = os.fstat(kwargs["cwd_fd"])
    replacement = parent / "replacement.md"
    replacement.write_text("# Concurrent replacement\n", encoding="utf-8")
    os.replace(replacement, markdown)
    parent.rename(held_parent)
    parent.symlink_to(outside, target_is_directory=True)
    held = os.stat(held_parent)
    assert (bound.st_dev, bound.st_ino) == (held.st_dev, held.st_ino), kwargs
    return original_run(cmd, **kwargs)


lark_adapter._run = racing_run
try:
    payload = lark_adapter.docs_create_from_markdown(
        markdown,
        title="t",
        target={"kind": "wiki", "token": "w"},
    )
finally:
    lark_adapter._run = original_run

assert payload["data"]["doc_id"] == "docX1", payload
assert parent.is_symlink()
assert (outside / "spec.md").read_text(encoding="utf-8") == "# Outside secret\n"
assert (outside / "sentinel.txt").read_text(encoding="utf-8") == "outside-sentinel\n"
assert not list(held_parent.glob(".*.lark-*.md"))
log = (root / "calls.log").read_text(encoding="utf-8")
assert "ARGV: docs +create" in log and "--content -" in log, log
assert "STDIN_HEAD: # Inside" in log, log
assert f"CWD: {held_parent}" in log and f"CWD: {outside}" not in log, log

parent.unlink()
held_parent.rename(parent)
assert markdown.read_text(encoding="utf-8") == "# Concurrent replacement\n"
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "docs parent rebind crossed directory binding: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_replace_markdown_body_uses_atomic_cas() {
  start_test "replace_markdown_body 的 path-namespace CAS 保全命名版本"
  local tmp; tmp=$(mktemp -d)
  local out rc

  out=$(python3 - "$tmp" <<'PY' 2>&1
import sys
from pathlib import Path

from _lib import atomic_file
from _lib.lark_adapter import LarkAdapterError, replace_markdown_body

root = Path(sys.argv[1]).resolve()
path = root / "body.md"
original_rename = atomic_file._rename_noreplace


def run_race(kind: str, concurrent_text: str) -> None:
    path.write_text("# Old\n", encoding="utf-8")

    def racing_rename(directory_fd: int, source: str, destination: str) -> None:
        before_target_claim = (
            kind == "before_claim"
            and source == path.name
            and destination.startswith(f".{path.name}.pmai-cas-original-")
        )
        before_target_install = (
            kind == "before_install"
            and destination == path.name
            and ".pmai-stage-claim-" in source
        )
        if before_target_claim or before_target_install:
            path.write_text(concurrent_text, encoding="utf-8")
        original_rename(directory_fd, source, destination)

    atomic_file._rename_noreplace = racing_rename
    try:
        replace_markdown_body(
            path,
            "# New\n",
            expected_text="# Old\n",
            require_canonical_path=True,
        )
    except LarkAdapterError as exc:
        assert exc.kind == "concurrent_update", (kind, exc.kind, str(exc))
    else:
        raise AssertionError(f"{kind} race unexpectedly succeeded")
    finally:
        atomic_file._rename_noreplace = original_rename

    assert path.read_text(encoding="utf-8") == concurrent_text, kind


run_race("before_claim", "# Concurrent before claim\n")
assert not list(root.glob(".body.md.pmai-cas-original-*"))

run_race("before_install", "# Concurrent before install\n")
recovery = list(root.glob(".body.md.pmai-cas-original-*"))
assert len(recovery) == 1, recovery
assert recovery[0].read_text(encoding="utf-8") == "# Old\n"
stages = list(root.glob(".body.md.pmai-cas-stage-*"))
assert len(stages) == 1, stages
assert stages[0].read_text(encoding="utf-8") == "# New\n"
try:
    replace_markdown_body(
        path,
        "# Newer\n",
        expected_text="# Concurrent before install\n",
        require_canonical_path=True,
    )
except LarkAdapterError as exc:
    assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    assert str(recovery[0]) in str(exc), str(exc)
else:
    raise AssertionError("unfinished recovery state was silently skipped")
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "原子 CAS 未保全并发内容和原件: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_replace_markdown_body_wraps_stage_fsync_failure() {
  start_test "replace_markdown_body 统一报告 stage 持久化失败且不改正式文件"
  local tmp; tmp=$(mktemp -d)
  local out rc
  printf '%s\n' '# Old' > "$tmp/body.md"

  out=$(python3 - "$tmp/body.md" <<'PY' 2>&1
import sys
import os
import stat
from pathlib import Path

from _lib import atomic_file
from _lib.lark_adapter import LarkAdapterError, replace_markdown_body

path = Path(sys.argv[1]).resolve()
original_fsync = atomic_file.os.fsync
stage_fsync_failed = False


def failing_fsync(fd):
    global stage_fsync_failed
    if not stage_fsync_failed and stat.S_ISREG(os.fstat(fd).st_mode):
        stage_fsync_failed = True
        raise OSError(28, "injected stage fsync failure")
    return original_fsync(fd)


atomic_file.os.fsync = failing_fsync
try:
    replace_markdown_body(
        path,
        "# New\n",
        expected_text="# Old\n",
        require_canonical_path=True,
    )
except LarkAdapterError as exc:
    assert exc.kind == "validation", (exc.kind, str(exc))
    assert "暂存文件" in str(exc), str(exc)
else:
    raise AssertionError("stage fsync failure unexpectedly succeeded")
finally:
    atomic_file.os.fsync = original_fsync

assert stage_fsync_failed
assert path.read_text(encoding="utf-8") == "# Old\n"
assert not list(path.parent.glob(".body.md.pmai-cas-stage-*"))
assert not list(path.parent.glob(".body.md.pmai-cas-original-*"))
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "stage fsync failure escaped adapter or changed formal file: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}


test_replace_markdown_body_escalates_cleanup_fsync_failure() {
  start_test "replace_markdown_body 清理目录 fsync 失败时保留恢复路径并升级错误"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '# Old' > "$tmp/body.md"

  local out rc
  out=$(python3 - "$tmp/body.md" <<'PY' 2>&1
import os
import stat
import sys
from pathlib import Path

from _lib import atomic_file
from _lib.lark_adapter import LarkAdapterError, replace_markdown_body

path = Path(sys.argv[1]).resolve()
original_fsync = atomic_file.os.fsync
stage_fsync_failed = False
cleanup_fsync_failed = False


def failing_fsync(fd):
    global stage_fsync_failed, cleanup_fsync_failed
    mode = os.fstat(fd).st_mode
    if not stage_fsync_failed and stat.S_ISREG(mode):
        stage_fsync_failed = True
        raise OSError(28, "injected stage fsync failure")
    if stage_fsync_failed and not cleanup_fsync_failed and stat.S_ISDIR(mode):
        cleanup_fsync_failed = True
        raise OSError(5, "injected cleanup directory fsync failure")
    return original_fsync(fd)


atomic_file.os.fsync = failing_fsync
try:
    replace_markdown_body(
        path,
        "# New\n",
        expected_text="# Old\n",
        require_canonical_path=True,
    )
except LarkAdapterError as exc:
    assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    assert "暂存文件清理失败" in str(exc), str(exc)
    claims = list(
        path.parent.glob(
            ".body.md.pmai-cas-stage-*.pmai-cleanup-claim-*"
        )
    )
    assert len(claims) == 1, claims
    assert claims[0].read_text(encoding="utf-8") == "# New\n"
    assert str(claims[0]) in str(exc), str(exc)
else:
    raise AssertionError("cleanup fsync failure unexpectedly succeeded")
finally:
    atomic_file.os.fsync = original_fsync

assert stage_fsync_failed and cleanup_fsync_failed
assert path.read_text(encoding="utf-8") == "# Old\n"
assert not list(path.parent.glob(".body.md.pmai-cas-original-*"))
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "cleanup fsync failure was not preserved as recovery state: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}


test_bound_markdown_write_uses_bound_directory_cas() {
  start_test "BoundMarkdown 写回固定目录 fd 且校验原文件 inode"
  local tmp; tmp=$(mktemp -d)
  local out rc
  printf '%s\n' '# Old' > "$tmp/body.md"

  out=$(python3 - "$tmp/body.md" <<'PY' 2>&1
import os
import sys
from pathlib import Path

from _lib import lark_adapter

path = Path(sys.argv[1])
path_replace = lark_adapter.replace_text_if_unchanged


def forbidden_path_replace(*_args, **_kwargs):
    raise AssertionError("BoundMarkdown unexpectedly reopened the pathname")


lark_adapter.replace_text_if_unchanged = forbidden_path_replace
try:
    with lark_adapter.bind_markdown(path) as markdown:
        lark_adapter.replace_markdown_body(
            markdown,
            "# New\n",
            expected_text="# Old\n",
        )
finally:
    lark_adapter.replace_text_if_unchanged = path_replace

assert path.read_text(encoding="utf-8") == "# New\n"

path.write_text("# Same\n", encoding="utf-8")
with lark_adapter.bind_markdown(path) as markdown:
    replacement = path.with_name("replacement.md")
    replacement.write_text("# Same\n", encoding="utf-8")
    os.replace(replacement, path)
    try:
        lark_adapter.replace_markdown_body(
            markdown,
            "# Wrong\n",
            expected_text="# Same\n",
        )
    except lark_adapter.LarkAdapterError as exc:
        assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    else:
        raise AssertionError("same-content replacement inode was accepted")

assert path.read_text(encoding="utf-8") == "# Same\n"

recovery = path.with_name(".body.md.pmai-cas-original-test")
recovery.write_text("# Prior original\n", encoding="utf-8")
try:
    with lark_adapter.bind_markdown(path):
        pass
except lark_adapter.LarkAdapterError as exc:
    assert exc.kind == "concurrent_update", (exc.kind, str(exc))
    assert str(recovery) in str(exc), str(exc)
else:
    raise AssertionError("unfinished CAS recovery state was published")
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "BoundMarkdown CAS 未绑定目录或文件身份: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}

test_bound_cwd_uses_fchdir_without_fd_paths() {
  start_test "绑定 cwd 通过 fchdir 进入目录且不依赖 fd 伪路径"
  local tmp; tmp=$(mktemp -d)
  local out rc

  out=$(python3 - "$tmp" <<'PY' 2>&1
import os
import sys
from pathlib import Path

from _lib import lark_adapter

root = Path(sys.argv[1]).resolve()
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
try:
    result = lark_adapter._run(
        [sys.executable, "-c", "import os; print(os.getcwd())"],
        cwd=root,
        cwd_fd=directory_fd,
    )
finally:
    os.close(directory_fd)

assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
assert Path(result.stdout.strip()).resolve() == root, result.stdout
print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "fd cwd 未通过 fchdir 进入绑定目录: rc=$rc out=$out"
    rm -rf "$tmp"
    return
  fi
  pass_test
  rm -rf "$tmp"
}


test_bound_cwd_preexec_failure_fails_closed() {
  start_test "绑定 cwd 的 fchdir/preexec 失败时明确失败关闭"
  local tmp; tmp=$(mktemp -d)
  local out rc

  out=$(python3 - "$tmp" <<'PY' 2>&1
import os
import sys
from pathlib import Path

from _lib import lark_adapter

root = Path(sys.argv[1]).resolve()
directory_fd = os.open(root, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
original_fchdir = lark_adapter.os.fchdir


def failing_fchdir(_fd):
    raise OSError(13, "injected fchdir failure")


lark_adapter.os.fchdir = failing_fchdir
try:
    try:
        lark_adapter._run(
            [sys.executable, "-c", "print('unexpected')"],
            cwd=root,
            cwd_fd=directory_fd,
        )
    except lark_adapter.LarkAdapterError as exc:
        assert exc.kind == "validation", (exc.kind, str(exc))
        assert "已绑定目录" in str(exc), str(exc)
    else:
        raise AssertionError("fchdir/preexec failure unexpectedly succeeded")
finally:
    lark_adapter.os.fchdir = original_fchdir
    os.close(directory_fd)

print("OK")
PY
  )
  rc=$?
  if [ "$rc" -ne 0 ] || [ "$out" != "OK" ]; then
    _fail "fchdir/preexec failure did not fail closed: rc=$rc out=$out"
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
  # lark-cli 实际收到的 stdin 首行必须是正文，不能是 --- 或 frontmatter key
  if ! grep -q "STDIN_HEAD: # 真正文" "$log"; then
    _fail "frontmatter 未剥离；got: $(cat "$log")"
    cat "$log" >&2
    rm -rf "$tmp"
    return
  fi
  if grep -q "STDIN_HEAD: ---" "$log" || grep -q "STDIN_HEAD: lark_doc_id" "$log"; then
    _fail "frontmatter 泄漏进正文；got: $(grep STDIN_HEAD "$log")"
    rm -rf "$tmp"
    return
  fi
  # stdin 发送不得创建临时文件，原文件不动
  if find "$tmp" -maxdepth 1 -name '.*.lark-*.md' | grep -q .; then
    _fail "stdin 发送仍创建了临时文件：$(ls -A "$tmp")"
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
  if grep -q "STDIN_HEAD: # 覆盖正文" "$log" \
     && ! grep -q "STDIN_HEAD: ---" "$log"; then
    pass_test
  else
    _fail "覆盖发布未剥离 frontmatter；got: $(grep STDIN_HEAD "$log")"
    cat "$log" >&2
  fi
  rm -rf "$tmp"
}

test_docs_create_no_frontmatter_uses_stdin() {
  start_test "无 frontmatter 时也通过 stdin 发送且不创建临时文件"
  local tmp; tmp=$(mktemp -d)
  printf '%s\n' '# 无 fm' '正文' > "$tmp/plain.md"
  local log="$tmp/calls.log"
  FAKE_LARK_LOG="$log" python3 - <<PY
from pathlib import Path
from _lib.lark_adapter import docs_create_from_markdown
docs_create_from_markdown(Path("$tmp/plain.md"), title="t",
                          target={"kind": "wiki", "token": "w"})
PY
  if grep -q -- '--content -' "$log" \
     && grep -q 'STDIN_HEAD: # 无 fm' "$log" \
     && ! find "$tmp" -maxdepth 1 -name '.*.lark-*.md' | grep -q .; then
    pass_test
  else
    _fail "无 frontmatter 未通过 stdin 安全发送；log: $(cat "$log")；目录: $(ls -A "$tmp")"
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
test_docs_update_rejects_all_unverifiable_results
test_markdown_must_be_path
test_markdown_missing_file_rejected
test_api_json_passthrough
test_json_entrypoints_reject_failure_envelopes
test_docs_fetch_im_markdown_requires_1_0_58
test_drive_comment_set_solved_uses_patch_contract
test_drive_comment_reply_create_uses_reply_contract
test_drive_comments_page_passes_explicit_solved_filter
test_subprocess_failure_raises
test_successful_markdown_command_invalid_output_is_redacted
test_missing_cli_in_path
test_doctor_subcommand_happy
test_parse_frontmatter
test_parse_frontmatter_none
test_write_frontmatter_preserves_unknown_yaml
test_write_frontmatter_rejects_line_break_injection
test_replace_markdown_body_preserves_frontmatter
test_path_apis_and_bound_markdown_accept_parent_alias
test_replace_markdown_body_rejects_rebound_parent_symlink
test_replace_markdown_body_rejects_symlink_and_fifo_without_blocking
test_docs_send_rejects_symlink_and_fifo_without_blocking
test_docs_send_entry_swap_and_parent_rebind_uses_stdin
test_replace_markdown_body_uses_atomic_cas
test_replace_markdown_body_wraps_stage_fsync_failure
test_replace_markdown_body_escalates_cleanup_fsync_failure
test_bound_markdown_write_uses_bound_directory_cas
test_bound_cwd_uses_fchdir_without_fd_paths
test_bound_cwd_preexec_failure_fails_closed
test_docs_create_strips_frontmatter
test_docs_update_strips_frontmatter
test_docs_create_no_frontmatter_uses_stdin

report_results "lark-adapter"
