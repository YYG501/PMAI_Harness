#!/usr/bin/env bash
# check-gstack-browser.sh — lightweight diagnostics for gstack browse/design.
#
# Default mode avoids starting the gstack browse daemon. Use --browser-smoke or
# --smoke only when the user explicitly wants an active probe.
set -uo pipefail

RUN_BROWSER_SMOKE=0
RUN_DESIGN_SMOKE=0
DOCTOR_MODE=0
JSON_OUT=""
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
BROWSE_BIN=""
DESIGN_BIN=""

usage() {
  cat <<EOF
Usage:
  check-gstack-browser.sh [--doctor] [--browser-smoke|--smoke] [--json-out PATH]

Checks:
  - gstack browse/design binaries
  - localhost bind permission without starting browse
  - optional active browser smoke for local file navigation
  - optional active design compare-board smoke with --smoke

Notes:
  - --doctor is a passive check. It does not prove the browser can launch.
    Run --browser-smoke before browser-backed visual or behavior audits.
  - --smoke includes --browser-smoke plus the design compare-board smoke.
  - Codex sandbox may block localhost bind with EPERM. That means runtime
    restriction, not necessarily a broken gstack browser.
  - This script intentionally does not use "browse status" as a passive check,
    because that command can start a daemon.
EOF
}

ok() {
  echo "  OK: $*"
  PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
  echo "  WARN: $*"
  WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
  echo "  FAIL: $*"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

while [ $# -gt 0 ]; do
  case "$1" in
    --browser-smoke) RUN_BROWSER_SMOKE=1 ;;
    --smoke) RUN_BROWSER_SMOKE=1; RUN_DESIGN_SMOKE=1 ;;
    --json-out) JSON_OUT="${2:?--json-out needs path}"; shift ;;
    --doctor) DOCTOR_MODE=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

find_first_executable() {
  local env_name="$1"
  shift
  local value candidate

  value="${!env_name:-}"
  if [ -n "$value" ] && [ -x "$value" ]; then
    echo "$value"
    return 0
  fi

  for candidate in "$@"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

check_binaries() {
  local command_browse command_design

  command_browse=$(command -v browse 2>/dev/null || true)
  command_design=$(command -v design 2>/dev/null || true)

  BROWSE_BIN=$(find_first_executable GSTACK_BROWSE_BIN \
    "$command_browse" \
    "$HOME/.Codex/skills/gstack/browse/dist/browse" \
    "$HOME/.agents/skills/gstack/browse/dist/browse" \
    "$HOME/.claude/skills/gstack/browse/dist/browse" \
    "$HOME/.claude/skills/gstack/.agents/skills/gstack-browse/dist/browse" \
    2>/dev/null || true)

  DESIGN_BIN=$(find_first_executable GSTACK_DESIGN_BIN \
    "$command_design" \
    "$HOME/.agents/skills/gstack/design/dist/design" \
    "$HOME/.claude/skills/gstack/design/dist/design" \
    "$HOME/.claude/skills/gstack/.agents/skills/gstack-design-shotgun/dist/design" \
    2>/dev/null || true)

  if [ -n "$BROWSE_BIN" ]; then
    ok "gstack browse binary found: $BROWSE_BIN"
  else
    warn "gstack browse binary not found; browser-backed mockup checks will fall back"
  fi

  if [ -n "$DESIGN_BIN" ]; then
    ok "gstack design binary found: $DESIGN_BIN"
  else
    warn "gstack design binary not found; /design-shotgun compare board is unavailable"
  fi
}

probe_localhost_bind() {
  local out rc

  if ! command -v python3 >/dev/null 2>&1; then
    warn "python3 not found; cannot probe localhost bind permission"
    return
  fi

  out=$(python3 - <<'PY'
import errno
import socket
import sys

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind(("127.0.0.1", 0))
    print("OK")
    sys.exit(0)
except PermissionError as exc:
    print(f"EPERM: {exc}")
    sys.exit(13)
except OSError as exc:
    if exc.errno == errno.EPERM:
        print(f"EPERM: {exc}")
        sys.exit(13)
    print(f"OSERROR:{exc.errno}: {exc}")
    sys.exit(1)
finally:
    try:
        s.close()
    except Exception:
        pass
PY
)
  rc=$?

  case "$rc" in
    0) ok "localhost bind probe passed (127.0.0.1)" ;;
    13) warn "localhost bind blocked with EPERM; likely Codex sandbox/runtime restriction, not a broken gstack browser" ;;
    *) warn "localhost bind probe failed: $out" ;;
  esac
}

classify_browse_error() {
  local out="$1"
  local last_line
  last_line=$(printf "%s\n" "$out" | tail -1)

  if printf "%s\n" "$out" | grep -qiE "Executable doesn't exist|ms-playwright|playwright.*install|browserType\\.launch"; then
    warn "browse smoke failed: Playwright Chromium is missing. Install browser deps for gstack browse (for example: npx playwright install chromium) or run in a runtime with bundled Chromium."
    return
  fi

  if printf "%s\n" "$out" | grep -qiE "app\\.icns|/Applications/.+Operation not permitted|/Applications/.+EPERM"; then
    warn "browse smoke failed: system Chrome headed fallback hit macOS app bundle permission. Prefer Playwright Chromium, or fix the gstack headed Chrome icon-copy path before relying on browse evidence."
    return
  fi

  if [ -n "$last_line" ]; then
    warn "browse smoke failed at file:// navigation: $last_line"
  else
    warn "browse smoke failed at file:// navigation"
  fi
}

run_browser_smoke() {
  local tmp html shot text_out snapshot_out goto_out rc

  if [ -z "$BROWSE_BIN" ]; then
    warn "--browser-smoke requested but browse binary is unavailable"
    return
  fi

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/pmai-gstack-browser-smoke.XXXXXX") || {
    warn "could not create smoke temp dir"
    return
  }
  html="$tmp/smoke.html"
  shot="$tmp/smoke.png"

  cat > "$html" <<'HTML'
<!doctype html>
<html>
  <body>
    <h1>GStack Browser Smoke OK</h1>
    <button>Test Button</button>
  </body>
</html>
HTML

  goto_out=$("$BROWSE_BIN" goto "file://$html" 2>&1 >/dev/null)
  rc=$?
  if [ "$rc" != "0" ]; then
    classify_browse_error "$goto_out"
    return
  fi

  text_out=$("$BROWSE_BIN" text 2>/dev/null || true)
  if printf "%s\n" "$text_out" | grep -q "GStack Browser Smoke OK"; then
    ok "browse smoke text extraction passed"
  else
    warn "browse smoke text extraction did not include expected text"
  fi

  snapshot_out=$("$BROWSE_BIN" snapshot -i 2>/dev/null || true)
  if printf "%s\n" "$snapshot_out" | grep -q "Test Button"; then
    ok "browse smoke snapshot passed"
  else
    warn "browse smoke snapshot did not include expected button"
  fi

  if "$BROWSE_BIN" screenshot "$shot" >/dev/null 2>&1 && [ -s "$shot" ]; then
    ok "browse smoke screenshot saved"
  else
    warn "browse smoke screenshot failed"
  fi

  if [ "$RUN_DESIGN_SMOKE" = "1" ]; then
    run_design_board_smoke "$shot" "$tmp"
  fi
}

run_design_board_smoke() {
  local image="$1"
  local tmp="$2"
  local out rc

  if [ -z "$DESIGN_BIN" ]; then
    warn "--smoke requested but design binary is unavailable"
    return
  fi
  if [ ! -s "$image" ]; then
    warn "design board smoke skipped because browser screenshot is missing"
    return
  fi
  if ! command -v timeout >/dev/null 2>&1; then
    warn "design board smoke skipped because timeout command is unavailable"
    return
  fi

  out=$(timeout 12 "$DESIGN_BIN" compare \
    --images "$image,$image" \
    --output "$tmp/design-board.html" \
    --serve \
    --no-daemon 2>&1)
  rc=$?

  if printf "%s\n" "$out" | grep -q "SERVE_STARTED" && [ -s "$tmp/design-board.html" ]; then
    ok "design compare board smoke started successfully"
  elif [ "$rc" = "124" ] && [ -s "$tmp/design-board.html" ]; then
    ok "design compare board smoke produced board before timeout"
  else
    warn "design compare board smoke failed: $(printf "%s" "$out" | tail -1)"
  fi
}

echo "gstack browser/design diagnostics"
check_binaries
probe_localhost_bind

if [ "$RUN_BROWSER_SMOKE" = "1" ]; then
  run_browser_smoke
elif [ "$DOCTOR_MODE" = "1" ]; then
  echo "  INFO: passive diagnostics only; run check-gstack-browser.sh --browser-smoke before browser-backed visual/behavior audits"
elif [ "$DOCTOR_MODE" = "0" ]; then
  echo "  INFO: active browse/design smoke skipped; pass --browser-smoke to start browser checks"
fi

write_json_result() {
  [ -n "$JSON_OUT" ] || return
  local status tmp active_browser active_design out_dir
  status="pass"
  if [ "$RUN_BROWSER_SMOKE" != "1" ]; then
    status="skipped"
  elif [ "$FAIL_COUNT" -gt 0 ]; then
    status="fail"
  elif [ "$WARN_COUNT" -gt 0 ]; then
    status="limited"
  fi
  active_browser=false
  active_design=false
  [ "$RUN_BROWSER_SMOKE" = "1" ] && active_browser=true
  [ "$RUN_DESIGN_SMOKE" = "1" ] && active_design=true
  out_dir="$(dirname "$JSON_OUT")"
  if ! mkdir -p "$out_dir"; then
    fail "cannot create json output directory: $out_dir"
    return
  fi
  tmp="${JSON_OUT}.tmp"
  if ! cat > "$tmp" <<JSON
{"status":"$status","active_browser_smoke":$active_browser,"active_design_smoke":$active_design,"pass_count":$PASS_COUNT,"warn_count":$WARN_COUNT,"fail_count":$FAIL_COUNT,"checked_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
  then
    fail "cannot write json result: $JSON_OUT"
    rm -f "$tmp" 2>/dev/null || true
    return
  fi
  if ! mv "$tmp" "$JSON_OUT"; then
    fail "cannot move json result into place: $JSON_OUT"
    rm -f "$tmp" 2>/dev/null || true
  fi
}

write_json_result

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 2
fi
if [ "$WARN_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
