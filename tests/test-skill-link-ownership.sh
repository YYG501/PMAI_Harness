#!/usr/bin/env bash
# Host skill exposure must never replace an unowned shared-resource path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/assert.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LINK_HELPER="$REPO_ROOT/scripts/_lib/skill-links.sh"

test_installers_use_shared_ownership_helper() {
  start_test "skill links: install and upgrade share the ownership guard"
  if [ ! -f "$LINK_HELPER" ]; then
    _fail "missing shared ownership helper: $LINK_HELPER"
    return
  fi
  local file
  for file in "$REPO_ROOT/bin/pmai-install" "$REPO_ROOT/bin/pmai-upgrade" "$REPO_ROOT/bin/pmai-uninstall"; do
    if ! grep -q 'skill-links.sh' "$file"; then
      _fail "$(basename "$file") does not load skill-links.sh"
      return
    fi
  done
  pass_test
}

test_global_install_mutators_use_shared_lock_helper() {
  start_test "global install lock: four global entrypoints share one helper"
  local file
  for file in \
    "$REPO_ROOT/bin/pmai-install" \
    "$REPO_ROOT/bin/pmai-upgrade" \
    "$REPO_ROOT/bin/pmai-doctor" \
    "$REPO_ROOT/bin/pmai-uninstall"; do
    if ! grep -q 'global-install-lock.sh' "$file" \
      || ! grep -q 'pmai_hold_global_install_lock' "$file"; then
      _fail "$(basename "$file") must acquire the shared global install lock"
      return
    fi
  done
  pass_test
}

test_global_install_lock_serializes_doctor_and_uninstall() {
  start_test "global install lock: doctor and uninstall serialize one global install"
  local t framework fake_bin doctor_pid uninstall_pid real_python rc=0
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-global-install-lock.XXXXXX")
  framework="$t/framework"
  fake_bin="$t/fake-bin"
  real_python=$(command -v python3)
  mkdir -p "$framework/bin" "$framework/scripts/_lib" "$framework/.git" "$fake_bin"
  cp "$REPO_ROOT/bin/pmai-doctor" "$framework/bin/pmai-doctor"
  cp "$REPO_ROOT/scripts/_lib/global-install-lock.sh" \
    "$framework/scripts/_lib/global-install-lock.sh"
  cp "$REPO_ROOT/scripts/_lib/global_install_lock.py" \
    "$framework/scripts/_lib/global_install_lock.py"
  cp "$LINK_HELPER" "$framework/scripts/_lib/skill-links.sh"
  ln -s "$REPO_ROOT/skills" "$framework/skills"
  printf '0.0.0\n' > "$framework/VERSION"

  # The first doctor has already passed its outer and target-version lock
  # acquisition before it reaches git. Hold it there so the second real CLI
  # cannot start its destructive global-uninstall body.
  cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -u
if [ ! -e "$FAKE_GIT_ENTERED" ]; then
  : > "$FAKE_GIT_ENTERED"
  while [ ! -e "$FAKE_GIT_RELEASE" ]; do
    sleep 0.02
  done
fi
exit 0
EOF
  cat > "$fake_bin/rm" <<'EOF'
#!/usr/bin/env bash
set -u
if [ "${FAKE_RM_TRACK_UNINSTALL:-0}" = "1" ]; then
  printf 'entered\n' > "$FAKE_RM_ENTERED"
fi
exec /bin/rm "$@"
EOF
  cat > "$fake_bin/python3" <<'EOF'
#!/usr/bin/env bash
set -u
for arg in "$@"; do
  case "$arg" in
    */pmai-uninstall)
      : > "$FAKE_UNINSTALL_STARTED"
      break
      ;;
  esac
done
exec "$REAL_PYTHON3" "$@"
EOF
  chmod +x "$framework/bin/pmai-doctor" "$fake_bin/git" "$fake_bin/rm" \
    "$fake_bin/python3"

  (
    export HOME="$t/user"
    export PMAI_HOME="$framework"
    export CODEX_HOME="$HOME/.codex"
    export KIMI_CODE_HOME="$HOME/.kimi-code"
    export OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
    export PMAI_GLOBAL_INSTALL_LOCK_PATH="$t/global-install.lock"
    export FAKE_GIT_ENTERED="$t/doctor-entered"
    export FAKE_GIT_RELEASE="$t/release-doctor"
    export FAKE_RM_ENTERED="$t/uninstall-entered"
    export FAKE_UNINSTALL_STARTED="$t/uninstall-started"
    export REAL_PYTHON3="$real_python"
    export PATH="$fake_bin:$PATH"

    stop_process() {
      local pid="$1"
      kill -TERM "$pid" 2>/dev/null || :
      for _ in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.02
      done
      if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || :
      fi
      wait "$pid" 2>/dev/null || :
    }

    "$REPO_ROOT/bin/pmai-doctor" > "$t/doctor.out" 2>&1 &
    doctor_pid=$!
    for _ in $(seq 1 100); do
      [ -e "$FAKE_GIT_ENTERED" ] && break
      sleep 0.02
    done
    if [ ! -e "$FAKE_GIT_ENTERED" ]; then
      : > "$FAKE_GIT_RELEASE"
      stop_process "$doctor_pid"
      exit 2
    fi

    FAKE_RM_TRACK_UNINSTALL=1 \
      "$REPO_ROOT/bin/pmai-uninstall" --force --keep-state \
      > "$t/uninstall.out" 2>&1 &
    uninstall_pid=$!
    for _ in $(seq 1 100); do
      [ -e "$FAKE_UNINSTALL_STARTED" ] && break
      sleep 0.02
    done
    if [ ! -e "$FAKE_UNINSTALL_STARTED" ]; then
      : > "$FAKE_GIT_RELEASE"
      stop_process "$doctor_pid"
      stop_process "$uninstall_pid"
      exit 3
    fi
    sleep 0.2
    if [ -e "$FAKE_RM_ENTERED" ]; then
      : > "$FAKE_GIT_RELEASE"
      stop_process "$doctor_pid"
      stop_process "$uninstall_pid"
      exit 4
    fi

    : > "$FAKE_GIT_RELEASE"
    for _ in $(seq 1 250); do
      [ -e "$FAKE_RM_ENTERED" ] && break
      sleep 0.02
    done
    if [ ! -e "$FAKE_RM_ENTERED" ]; then
      rc=5
      stop_process "$doctor_pid"
      stop_process "$uninstall_pid"
    else
      stop_process "$doctor_pid"
      stop_process "$uninstall_pid"
    fi
    exit "$rc"
  )
  rc=$?

  case "$rc" in
    0) pass_test ;;
    2) _fail "doctor did not reach the held git section" ;;
    3) _fail "uninstall contender did not start" ;;
    4) _fail "uninstall entered before doctor released the shared lock" ;;
    5) _fail "uninstall did not enter after doctor released the shared lock" ;;
    *) _fail "global lock serialization fixture failed with rc=$rc" ;;
  esac
  rm -rf "$t"
}

test_global_mutators_fail_closed_when_lock_verification_fails() {
  start_test "global install lock: doctor and uninstall stop on invalid inherited fd"
  local t install out rc

  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-global-install-lock-invalid.XXXXXX")
  install="$t/install"
  mkdir -p "$install" "$t/home"
  printf 'keep-me\n' > "$install/sentinel.txt"

  out=$(HOME="$t/home" PMAI_HOME="$install" \
    PMAI_GLOBAL_INSTALL_LOCK_PATH="$t/global-install.lock" \
    PMAI_GLOBAL_INSTALL_LOCK_FD=999999 \
    "$REPO_ROOT/bin/pmai-doctor" 2>&1)
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "全局安装锁无法验证"; then
    _fail "doctor should stop on invalid inherited lock fd: rc=$rc out=$out"
    rm -rf "$t"
    return
  fi

  out=$(HOME="$t/home" PMAI_HOME="$install" \
    PMAI_GLOBAL_INSTALL_LOCK_PATH="$t/global-install.lock" \
    PMAI_GLOBAL_INSTALL_LOCK_FD=999999 \
    "$REPO_ROOT/bin/pmai-uninstall" --force --keep-state 2>&1)
  rc=$?
  if [ "$rc" != "2" ] || ! echo "$out" | grep -q "全局安装锁无法验证"; then
    _fail "uninstall should stop on invalid inherited lock fd: rc=$rc out=$out"
  elif [ ! -f "$install/sentinel.txt" ]; then
    _fail "uninstall mutated PMAI_HOME after lock verification failed"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_global_install_lock_preserves_exec_signal_and_stdio_semantics() {
  start_test "global install lock: exec preserves PID, signals, stdio, and failure cleanup"
  local t helper child out rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-global-install-signals.XXXXXX")
  helper="$REPO_ROOT/scripts/_lib/global_install_lock.py"
  child="$t/child.sh"

  cat > "$child" <<'EOF'
#!/usr/bin/env bash
set -u
handle_signal() {
  printf '%s\n' "$1" > "$PMAI_TEST_SIGNAL_RECEIVED"
  exit "$2"
}
trap 'handle_signal HUP 129' HUP
trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM
printf '%s\n' "$$" > "$PMAI_TEST_CHILD_PID"
: > "$PMAI_TEST_SIGNAL_READY"
while [ ! -e "$PMAI_TEST_RELEASE" ]; do
  sleep 0.02
done
EOF
  chmod +x "$child"

  out=$(python3 - "$helper" "$child" "$t" <<'PY' 2>&1
from __future__ import annotations

import os
import pty
import resource
import signal
import subprocess
import sys
import time
from pathlib import Path

helper, child, raw_root = sys.argv[1:]
root = Path(raw_root)
base_command = [sys.executable, helper, "run", "--lock-path"]


def wait_for(path: Path, timeout: float = 5.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        time.sleep(0.02)
    raise AssertionError(f"timed out waiting for {path}")


def cleanup(proc: subprocess.Popen[bytes], release: Path) -> None:
    release.touch(exist_ok=True)
    if proc.poll() is not None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=2)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


for name, number, expected in (
    ("HUP", signal.SIGHUP, 129),
    ("INT", signal.SIGINT, 130),
    ("TERM", signal.SIGTERM, 143),
):
    ready = root / f"ready-{name}"
    received = root / f"received-{name}"
    child_pid_path = root / f"child-{name}.pid"
    release = root / f"release-{name}"
    env = os.environ.copy()
    env.update(
        PMAI_TEST_SIGNAL_READY=str(ready),
        PMAI_TEST_SIGNAL_RECEIVED=str(received),
        PMAI_TEST_CHILD_PID=str(child_pid_path),
        PMAI_TEST_RELEASE=str(release),
    )
    output_path = root / f"exec-{name}.out"
    with output_path.open("wb") as output:
        proc = subprocess.Popen(
            base_command
            + [str(root / "global-install.lock"), "--", "bash", child],
            env=env,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        try:
            wait_for(ready)
            child_pid = int(child_pid_path.read_text(encoding="utf-8").strip())
            if child_pid != proc.pid:
                raise AssertionError(
                    f"lock helper left a wrapper process: helper={proc.pid} child={child_pid}"
                )
            if os.getpgid(proc.pid) != proc.pid:
                raise AssertionError("exec changed the test process group")
            os.kill(proc.pid, number)
            returncode = proc.wait(timeout=5)
            actual_signal = received.read_text(encoding="utf-8").strip()
            if returncode != expected or actual_signal != name:
                raise AssertionError(
                    f"{name}: expected rc={expected}/signal={name}, "
                    f"got rc={returncode}/signal={actual_signal!r}"
                )
        finally:
            cleanup(proc, release)
    reacquire = subprocess.run(
        base_command
        + [str(root / "global-install.lock"), "--", "bash", "-c", "exit 0"],
        timeout=5,
        check=False,
    )
    if reacquire.returncode != 0:
        raise AssertionError(f"{name}: lock was not released")

wait_lock = root / "wait-signal.lock"
holder_ready = root / "holder-ready"
holder_release = root / "holder-release"
holder = subprocess.Popen(
    base_command
    + [
        str(wait_lock),
        "--",
        "bash",
        "-c",
        'touch "$1"; while [ ! -e "$2" ]; do sleep 0.02; done',
        "bash",
        str(holder_ready),
        str(holder_release),
    ],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
)
try:
    wait_for(holder_ready)
    contender = subprocess.Popen(
        base_command + [str(wait_lock), "--", "bash", "-c", "exit 0"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    time.sleep(0.1)
    os.kill(contender.pid, signal.SIGINT)
    _, contender_stderr = contender.communicate(timeout=5)
    contender_text = contender_stderr.decode("utf-8", errors="replace")
    if contender.returncode != 130 or "Traceback" in contender_text:
        raise AssertionError(
            "SIGINT while waiting for the lock should return 130 without traceback: "
            f"rc={contender.returncode} stderr={contender_text!r}"
        )
finally:
    holder_release.touch(exist_ok=True)
    try:
        holder.wait(timeout=5)
    except subprocess.TimeoutExpired:
        holder.kill()
        holder.wait(timeout=2)

stdin_result = subprocess.run(
    base_command
    + [
        str(root / "stdin.lock"),
        "--",
        "bash",
        "-c",
        'read -r value; test "$value" = ok',
    ],
    input=b"ok\n",
    timeout=5,
    check=False,
)
if stdin_result.returncode != 0:
    raise AssertionError("exec lock helper did not preserve stdin")

tty_result = root / "tty-result"
tty_pid, tty_master = pty.fork()
if tty_pid == 0:
    tty_probe = """
import os
import sys

tty_ok = all(os.isatty(fd) for fd in (0, 1, 2))
try:
    foreground_ok = os.tcgetpgrp(0) == os.getpgrp()
except OSError:
    foreground_ok = False
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write(f"{os.getpid()}|{int(tty_ok)}|{int(foreground_ok)}\\n")
"""
    command = base_command + [
        str(root / "tty.lock"),
        "--",
        sys.executable,
        "-c",
        tty_probe,
        str(tty_result),
    ]
    os.execvpe(command[0], command, os.environ.copy())

tty_deadline = time.monotonic() + 5
tty_status = None
while time.monotonic() < tty_deadline:
    waited_pid, status = os.waitpid(tty_pid, os.WNOHANG)
    if waited_pid == tty_pid:
        tty_status = status
        break
    time.sleep(0.02)
if tty_status is None:
    os.kill(tty_pid, signal.SIGKILL)
    os.waitpid(tty_pid, 0)
    os.close(tty_master)
    raise AssertionError("TTY probe timed out")
os.close(tty_master)
if not os.WIFEXITED(tty_status) or os.WEXITSTATUS(tty_status) != 0:
    raise AssertionError(f"TTY probe failed with wait status {tty_status}")
observed_pid, is_tty, is_foreground = tty_result.read_text(
    encoding="utf-8"
).strip().split("|")
if int(observed_pid) != tty_pid or is_tty != "1" or is_foreground != "1":
    raise AssertionError(
        "exec lock helper did not preserve controlling TTY semantics: "
        f"fork_pid={tty_pid} result={observed_pid}|{is_tty}|{is_foreground}"
    )

missing = root / "definitely-missing-executable"
failed = subprocess.run(
    base_command + [str(root / "exec-failure.lock"), "--", str(missing)],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=5,
    check=False,
)
stderr = failed.stderr.decode("utf-8", errors="replace")
if failed.returncode != 2 or "无法启动全局安装锁内命令" not in stderr:
    raise AssertionError(f"exec failure contract drifted: rc={failed.returncode} {stderr!r}")
if "Traceback" in stderr:
    raise AssertionError("exec failure leaked a traceback")
after_failure = subprocess.run(
    base_command
    + [str(root / "exec-failure.lock"), "--", "bash", "-c", "exit 0"],
    timeout=5,
    check=False,
)
if after_failure.returncode != 0:
    raise AssertionError("exec failure leaked the lock fd")


def restrict_fd_limit() -> None:
    _, hard_limit = resource.getrlimit(resource.RLIMIT_NOFILE)
    soft_limit = 64
    if hard_limit != resource.RLIM_INFINITY:
        soft_limit = min(soft_limit, hard_limit)
    resource.setrlimit(resource.RLIMIT_NOFILE, (soft_limit, hard_limit))


fd_failure = subprocess.run(
    base_command
    + [str(root / "fd-failure.lock"), "--", "bash", "-c", "exit 0"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=5,
    check=False,
    preexec_fn=restrict_fd_limit,
)
fd_stderr = fd_failure.stderr.decode("utf-8", errors="replace")
if (
    fd_failure.returncode != 2
    or "无法准备继承的全局安装锁" not in fd_stderr
    or "Traceback" in fd_stderr
):
    raise AssertionError(
        f"fd preparation failure contract drifted: rc={fd_failure.returncode} "
        f"stderr={fd_stderr!r}"
    )

direct = subprocess.run(
    base_command
    + [str(root / "direct-signal.lock"), "--", "bash", "-c", 'kill -TERM "$$"'],
    timeout=5,
    check=False,
)
if direct.returncode != -signal.SIGTERM:
    raise AssertionError(f"direct signal should remain native, got {direct.returncode}")
PY
  )
  rc=$?
  if [ "$rc" != "0" ]; then
    _fail "global lock exec contract failed: $out"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_foreign_shared_directory_is_preserved() {
  start_test "skill links: foreign _shared directory is rejected and preserved"
  local t src dst out rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-links.XXXXXX")
  src="$t/pmai/skills/_shared"
  dst="$t/host/skills/_shared"
  mkdir -p "$src" "$dst"
  printf 'third party\n' > "$dst/third-party.txt"

  # shellcheck disable=SC1090
  source "$LINK_HELPER"
  out=$(pmai_install_shared_link "$src" "$dst" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "foreign _shared directory should block installation"
  elif [ ! -f "$dst/third-party.txt" ] || [ -L "$dst" ]; then
    _fail "foreign _shared directory was modified"
  elif ! echo "$out" | grep -q "不属于 PMAI"; then
    _fail "ownership conflict guidance missing: $out"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_managed_shared_link_can_be_refreshed() {
  start_test "skill links: PMAI-owned _shared symlink can be refreshed"
  local t src dst
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-links.XXXXXX")
  src="$t/pmai/skills/_shared"
  dst="$t/host/skills/_shared"
  mkdir -p "$src" "$(dirname "$dst")"
  ln -s "$src" "$dst"

  # shellcheck disable=SC1090
  source "$LINK_HELPER"
  if ! pmai_install_shared_link "$src" "$dst" >/dev/null 2>&1; then
    _fail "managed _shared link should be replaceable"
  elif [ "$(readlink "$dst")" != "$src" ]; then
    _fail "managed _shared link target drifted"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_foreign_shared_symlink_is_preserved() {
  start_test "skill links: foreign _shared symlink is rejected and preserved"
  local t src foreign dst out rc
  t=$(mktemp -d "${TMPDIR:-/tmp}/pmai-skill-links.XXXXXX")
  src="$t/pmai/skills/_shared"
  foreign="$t/third-party/shared"
  dst="$t/host/skills/_shared"
  mkdir -p "$src" "$foreign" "$(dirname "$dst")"
  ln -s "$foreign" "$dst"

  # shellcheck disable=SC1090
  source "$LINK_HELPER"
  out=$(pmai_install_shared_link "$src" "$dst" 2>&1)
  rc=$?

  if [ "$rc" = "0" ]; then
    _fail "foreign _shared symlink should block installation"
  elif [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "$foreign" ]; then
    _fail "foreign _shared symlink was modified"
  elif ! echo "$out" | grep -q "不属于 PMAI"; then
    _fail "ownership conflict guidance missing: $out"
  else
    pass_test
  fi
  rm -rf "$t"
}

test_installers_use_shared_ownership_helper
test_global_install_mutators_use_shared_lock_helper
test_global_install_lock_serializes_doctor_and_uninstall
test_global_mutators_fail_closed_when_lock_verification_fails
test_global_install_lock_preserves_exec_signal_and_stdio_semantics
test_foreign_shared_directory_is_preserved
test_managed_shared_link_can_be_refreshed
test_foreign_shared_symlink_is_preserved

report_results "skill-link-ownership"
