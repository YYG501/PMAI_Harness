#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"
source "$SCRIPT_DIR/helpers/fixture.sh"

QF="$FRAMEWORK_ROOT/scripts/quick-fix.sh"

test_desc_sanitize() {
  start_test "scenario 17 desc sanitize strips special characters"
  fixture_setup
  desc=$'bad|line\n`$;tail'
  if (cd "$FIXTURE_DIR" && QUICK_FIX_COMMAND="mkdir -p docs && echo sanitize > docs/sanitize.md" QUICK_FIX_APPROVE=1 bash "$QF" "$desc" >/tmp/qf.out.$$ 2>/tmp/qf.err.$$); then
    subject=$(git -C "$FIXTURE_DIR" log --grep '^\[quick-fix\]' --format=%s -1)
    if echo "$subject" | grep -q '｜' \
      && ! echo "$subject" | grep -q '[|`$;]'; then
      pass_test
    else
      _fail "sanitized subject still contains forbidden characters: $subject"
    fi
  else
    _fail "sanitize quick-fix failed"
    cat /tmp/qf.out.$$ /tmp/qf.err.$$ >&2
  fi
  rm -f /tmp/qf.out.$$ /tmp/qf.err.$$
  fixture_teardown
}

test_desc_sanitize
report_results "quick-fix sanitize"
