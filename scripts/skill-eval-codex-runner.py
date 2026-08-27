#!/usr/bin/env python3
"""Run one Session Eval case through the Codex CLI.

The adapter owns process execution and runtime telemetry only. Git/file truth is
still collected by ``skill-eval.py`` after this process exits.
"""

from __future__ import annotations

import json
import os
import re
import selectors
import signal
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def git_value(workspace: Path, args: list[str]) -> str:
    completed = subprocess.run(
        ["git", "-C", str(workspace), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return "unknown"
    return completed.stdout.strip() or "unknown"


def append_event(path: Path | None, event: dict[str, Any]) -> None:
    if path is None:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def write_context_pack(case: dict[str, Any], workspace: Path) -> Path:
    """Write a compact navigation index outside the disposable workspace.

    The index gives the model a bounded starting point without becoming part of
    the Harness diff. It deliberately contains paths and metadata only; source
    files remain authoritative and must still be read when relevant.
    """
    pack_path = workspace.parent / "session-context-pack.md"
    input_block = case.get("input") if isinstance(case.get("input"), dict) else {}
    context = input_block.get("context") if isinstance(input_block.get("context"), list) else []
    skills = case.get("skills") if isinstance(case.get("skills"), list) else []
    harness = case.get("harness") if isinstance(case.get("harness"), dict) else {}
    lines = [
        "# Session Eval context index",
        "",
        "This is a navigation index for the isolated run, not a replacement for source files.",
        "Read only the listed Skill entrypoints and directly relevant workspace files; do not recursively inventory the repository.",
        "",
        "## Required Skill entrypoints",
    ]
    lines.extend(f"- $PMAI_HOME/skills/{item}/SKILL.md" for item in skills if isinstance(item, str))
    lines.extend(["", "## Case context"])
    lines.extend(f"- {item}" for item in context if isinstance(item, str))
    lines.extend(["", "## Harness boundaries"])
    lines.append(
        "- The Harness records the actual workspace changes independently; do not fabricate evidence."
    )
    lines.append(
        "- Modify only files required by the PM request. Protected paths and expected outcomes are hidden from the Runner."
    )
    lines.extend(["", "## Workspace navigation"])
    for relative in (
        "AGENTS.md",
        "CLAUDE.md",
        "PRODUCT.md",
        "PRODUCT-RULES.md",
        "DESIGN.md",
        "PRODUCT-STATE.md",
        ".pm-workflow/project.yml",
        ".pm-workflow/context",
        "docs/modules",
    ):
        candidate = workspace / relative
        if candidate.exists():
            if candidate.is_file():
                lines.append(f"- {relative} ({candidate.stat().st_size} bytes)")
            else:
                lines.append(f"- {relative}/ (directory; inspect only the relevant module)")
    pack_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return pack_path


def text_from_item(item: dict[str, Any]) -> str | None:
    value = item.get("text")
    if isinstance(value, str) and value.strip():
        return value.strip()
    content = item.get("content")
    if isinstance(content, list):
        parts = [entry.get("text") for entry in content if isinstance(entry, dict)]
        text = "".join(part for part in parts if isinstance(part, str))
        return text.strip() or None
    return None


def evidence_output(value: Any, *, limit: int = 4000) -> str:
    """Keep a small, redacted command result for the independent semantic Judge."""
    if not isinstance(value, str) or not value.strip():
        return ""
    text = value
    home = str(Path.home())
    if home and home != "/":
        text = text.replace(home, "~")
    text = re.sub(
        r"(?i)(api[_-]?key|access[_-]?token|secret|password)\s*[:=]\s*([^\s,;]+)",
        r"\1=[REDACTED]",
        text,
    )
    if len(text) > limit:
        return text[:limit] + "\n...[command output truncated]"
    return text


def record_provider_line(path: Path | None, line: bytes, elapsed_ms: int) -> None:
    """Record non-sensitive JSONL event metadata as an incremental heartbeat."""
    if path is None:
        return
    try:
        event = json.loads(line.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return
    if not isinstance(event, dict):
        return
    item = event.get("item") if isinstance(event.get("item"), dict) else {}
    append_event(
        path,
        {
            "kind": "provider_event",
            "event_type": str(event.get("type") or "unknown"),
            "item_type": str(item.get("type") or "") if item else "",
            "elapsed_ms": elapsed_ms,
        },
    )


def terminate_process_group(process: subprocess.Popen[bytes]) -> None:
    """Stop the CLI and descendants after a bounded timeout."""
    try:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
    except (OSError, ProcessLookupError):
        try:
            process.terminate()
        except OSError:
            pass
    try:
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        except (OSError, ProcessLookupError):
            try:
                process.kill()
            except OSError:
                pass
        process.wait()


def run_streaming(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    timeout_seconds: int,
    event_log: Path | None,
) -> dict[str, Any]:
    """Run Codex while retaining bounded timeout and incremental telemetry."""
    process = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    )
    assert process.stdout is not None
    assert process.stderr is not None
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ, "stdout")
    selector.register(process.stderr, selectors.EVENT_READ, "stderr")
    buffers = {"stdout": b"", "stderr": b""}
    chunks = {"stdout": bytearray(), "stderr": bytearray()}
    started = time.monotonic()
    timed_out = False
    try:
        while selector.get_map():
            remaining = timeout_seconds - (time.monotonic() - started)
            if remaining <= 0:
                timed_out = True
                terminate_process_group(process)
                break
            ready = selector.select(min(remaining, 1.0))
            if not ready:
                continue
            for key, _ in ready:
                stream = str(key.data)
                data = os.read(key.fileobj.fileno(), 65536)
                if not data:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    continue
                chunks[stream].extend(data)
                buffers[stream] += data
                while b"\n" in buffers[stream]:
                    line, buffers[stream] = buffers[stream].split(b"\n", 1)
                    if stream == "stdout":
                        record_provider_line(event_log, line, int((time.monotonic() - started) * 1000))
        if not timed_out:
            process.wait()
    finally:
        if timed_out:
            for stream in ("stdout", "stderr"):
                buffers[stream] = b""
        for key in list(selector.get_map().values()):
            try:
                selector.unregister(key.fileobj)
            except (KeyError, ValueError):
                pass
            try:
                key.fileobj.close()
            except OSError:
                pass
        selector.close()
    return {
        "stdout": bytes(chunks["stdout"]).decode("utf-8", errors="replace"),
        "stderr": bytes(chunks["stderr"]).decode("utf-8", errors="replace"),
        "returncode": process.returncode,
        "timed_out": timed_out,
    }


def token_usage_from_value(value: Any) -> dict[str, int] | None:
    if not isinstance(value, dict):
        return None
    input_tokens = value.get("input_tokens")
    output_tokens = value.get("output_tokens")
    total_tokens = value.get("total_tokens")
    if not (
        isinstance(input_tokens, int)
        and input_tokens >= 0
        and isinstance(output_tokens, int)
        and output_tokens >= 0
    ):
        return None
    if not isinstance(total_tokens, int) or total_tokens < 0:
        total_tokens = input_tokens + output_tokens
    return {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": total_tokens,
    }


def parse_events(raw: str) -> dict[str, Any]:
    transcript: list[str] = []
    tool_calls: list[dict[str, Any]] = []
    errors: list[str] = []
    diagnostics: list[str] = []
    token_usage: dict[str, int] | None = None
    thread_id = ""
    model = ""
    eval_result: dict[str, Any] | None = None

    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        event_type = event.get("type")
        if event_type == "thread.started":
            thread_id = str(event.get("thread_id") or "").strip()
        model = str(event.get("model") or model).strip()

        item = event.get("item")
        if isinstance(item, dict):
            item_type = item.get("type")
            if item_type in {"function_call", "command_execution", "tool_call"}:
                call = {
                    "type": str(item_type),
                    "name": str(item.get("name") or item.get("tool") or "unknown"),
                }
                for field in ("command", "arguments", "status", "exit_code"):
                    value = item.get(field)
                    if isinstance(value, (str, int, float, bool)):
                        call[field] = str(value)[:2000] if isinstance(value, str) else value
                output = evidence_output(item.get("aggregated_output"))
                if not output:
                    output = evidence_output(item.get("output"))
                if output:
                    call["output_excerpt"] = output
                tool_calls.append(call)
            if item_type == "agent_message":
                text = text_from_item(item)
                if text:
                    transcript.append(text[:4000])
                    marker = re.search(r"PMAI_EVAL_RESULT:\s*(\{.*\})", text)
                    if marker:
                        try:
                            candidate = json.loads(marker.group(1))
                        except json.JSONDecodeError:
                            candidate = None
                        if isinstance(candidate, dict):
                            eval_result = candidate
            if item_type == "error":
                message = str(item.get("message") or "runner item error").strip()
                if message:
                    diagnostics.append(message[:1000])
        if event_type in {"error", "turn.failed"}:
            message = event.get("message")
            if not message and isinstance(event.get("error"), dict):
                message = event["error"].get("message")
            if message:
                errors.append(str(message).strip()[:1000])

        payload = event.get("payload") if event_type == "event_msg" else event
        if isinstance(payload, dict) and payload.get("type") == "token_count":
            info = payload.get("info")
            total = info.get("total_token_usage") if isinstance(info, dict) else None
            parsed_usage = token_usage_from_value(total)
            if parsed_usage is not None:
                token_usage = parsed_usage
        if event_type == "turn.completed":
            parsed_usage = token_usage_from_value(event.get("usage"))
            if parsed_usage is not None:
                token_usage = parsed_usage

    return {
        "transcript": transcript,
        "tool_calls": tool_calls,
        "errors": errors,
        "diagnostics": diagnostics,
        "token_usage": token_usage,
        "thread_id": thread_id,
        "model": model,
        "eval_result": eval_result,
    }


def is_recoverable_completed_stream_failure(failure_reason: str, parsed: dict[str, Any]) -> bool:
    """Keep a complete result when the CLI disconnects after emitting its marker.

    The independent Harness/Judge still decides whether the claimed actions really
    happened. This narrow exception only prevents a post-result provider stream
    warning from discarding an otherwise complete, machine-readable result.
    """
    if "stream disconnected before completion" not in failure_reason.lower():
        return False
    transport_fragments = (
        "reconnecting",
        "stream disconnected",
        "transport error",
        "error decoding response body",
        "connection failed",
    )
    if any(
        not any(fragment in str(error).lower() for fragment in transport_fragments)
        for error in parsed.get("errors", [])
    ):
        return False
    claimed = parsed.get("eval_result")
    if not isinstance(claimed, dict):
        return False
    lifecycle = claimed.get("lifecycle")
    observations = claimed.get("observations")
    return (
        claimed.get("stopping_point") == "complete"
        and isinstance(lifecycle, list)
        and "complete" in lifecycle
        and isinstance(observations, list)
        and bool(observations)
    )


def prompt_for(case: dict[str, Any], workspace: Path) -> str:
    input_block = case.get("input") if isinstance(case.get("input"), dict) else {}
    prompt = str(input_block.get("prompt") or "").strip()
    context = input_block.get("context") if isinstance(input_block.get("context"), list) else []
    context_lines = "\n".join(f"- {item}" for item in context if isinstance(item, str))
    skills = case.get("skills") if isinstance(case.get("skills"), list) else []
    skill_lines = "\n".join(
        f"- $PMAI_HOME/skills/{item}/SKILL.md" for item in skills if isinstance(item, str)
    )
    harness = case.get("harness") if isinstance(case.get("harness"), dict) else {}
    context_pack = os.environ.get("PMAI_SESSION_CONTEXT", "").strip()
    boundary_lines = [
        "Harness file boundary:",
        "- The Harness independently checks all changed and protected paths after the run.",
        "- Do not modify files outside the PM request or claim actions that did not happen.",
    ]
    if context_pack:
        boundary_lines.append(f"- Read the temporary navigation index first: {context_pack}")
    protocol_lines = [
        "Machine-readable run note (untrusted; the evaluator verifies the actual workspace independently):",
        'PMAI_EVAL_RESULT: {"summary":"...","actions":["..."],"claimed_lifecycle":["..."],"claimed_stopping_point":"..."}',
        "Use plain-language action labels based only on actions actually performed.",
        "Do not invent evaluator criteria, expected tokens, or success claims.",
    ]
    return (
        "You are the Runner for a PMAI Session Eval. Work only inside the current Git workspace.\n"
        "Execute the PM intent below. Do not modify files outside the workspace, do not use network, "
        "and do not claim success unless the requested result is actually present.\n\n"
        "Use the current framework checkout exposed as PMAI_HOME. Read each listed PMAI skill entrypoint "
        "before acting, then follow its real workflow. Read referenced material when it is relevant to "
        "this case, keeping the investigation focused; do not spend the run recursively dumping unrelated "
        "documents or simulating completion in the final answer. This is a bounded harness run: avoid "
        "broad repository inventories, generic startup scans, repeated reads of unchanged files, and "
        "full-file dumps when a focused section is sufficient.\n"
        f"Required skill entrypoints:\n{skill_lines or '- none'}\n\n"
        + "\n".join(boundary_lines)
        + "\n\n"
        f"PM intent: {prompt}\n"
        f"Context:\n{context_lines or '- none'}\n\n"
        "After completing the task, briefly report the actions you actually performed.\n"
        "End your final response with one machine-readable run note in the form shown below. "
        "The note is not a pass signal and will not be trusted without independent evidence.\n\n"
        + "\n".join(protocol_lines)
    )


def cost_from_tokens(token_usage: dict[str, int] | None) -> dict[str, Any]:
    if token_usage is None:
        return {"status": "unavailable", "reason": "Codex did not emit a final token event"}
    try:
        input_rate = float(os.environ["PMAI_INPUT_COST_PER_1K_USD"])
        output_rate = float(os.environ["PMAI_OUTPUT_COST_PER_1K_USD"])
    except (KeyError, ValueError):
        return {"status": "unavailable", "reason": "No local pricing rates were configured"}
    amount = (
        token_usage["input_tokens"] / 1000 * input_rate
        + token_usage["output_tokens"] / 1000 * output_rate
    )
    return {"status": "reported", "currency": "USD", "amount_usd": round(amount, 8)}


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        case = payload["case"]
        evaluation_id = str(payload["evaluation_id"])
        harness = case.get("harness") if isinstance(case, dict) else None
        if not isinstance(harness, dict):
            raise RuntimeError(
                "session eval runner requires an isolated harness.workspace; "
                "refusing to use the current working directory"
            )
        workspace_raw = harness.get("workspace")
        if not isinstance(workspace_raw, str) or not workspace_raw.strip():
            raise RuntimeError("session eval runner requires harness.workspace")
        workspace = Path(workspace_raw).expanduser().resolve()
        if not workspace.is_dir():
            raise RuntimeError(f"workspace 不存在: {workspace}")
        event_log_raw = harness.get("event_log") if isinstance(harness, dict) else None
        event_log = Path(str(event_log_raw)) if event_log_raw else None
        baseline_revision = str(harness.get("baseline_commit") or "").strip() if isinstance(harness, dict) else ""
        consumer_revision = baseline_revision or git_value(workspace, ["rev-parse", "HEAD"])
        framework_root = Path(os.environ.get("PMAI_FRAMEWORK_ROOT", Path(__file__).resolve().parent.parent)).resolve()
        framework_revision = os.environ.get("PMAI_FRAMEWORK_REVISION", "").strip() or git_value(
            framework_root, ["rev-parse", "HEAD"]
        )

        started_at = iso_now()
        started = time.monotonic()
        append_event(event_log, {"kind": "lifecycle", "value": "started"})
        append_event(event_log, {"kind": "tool", "name": "codex.exec"})

        command = shlex.split(os.environ.get("PMAI_CODEX_COMMAND", "codex"))
        if not command:
            raise RuntimeError("PMAI_CODEX_COMMAND 为空")
        argv = [
            *command,
            "exec",
            "--approve-for-me",
            "--json",
            "--ephemeral",
            "--cd",
            str(workspace),
            # Harness creates a disposable Git workspace outside the user's
            # trusted roots. Never wait for an interactive trust prompt in the
            # non-interactive runner.
            "--skip-git-repo-check",
            "--ignore-rules",
            # Build finalization creates a detached validation worktree. The
            # workspace is disposable, so explicitly grant the CLI access to
            # its Git metadata instead of letting the host sandbox reject
            # `.git/worktrees` while the PMAI contract is being evaluated.
            "--add-dir",
            str((workspace / ".git").resolve()),
        ]
        if os.environ.get("PMAI_CODEX_IGNORE_USER_CONFIG") == "1":
            argv.append("--ignore-user-config")
        reasoning_effort = os.environ.get("PMAI_CODEX_REASONING_EFFORT", "medium").strip()
        if reasoning_effort:
            # Session Eval must be reproducible instead of inheriting an
            # interactive user's potentially very expensive xhigh setting.
            argv.extend(["-c", f"model_reasoning_effort={reasoning_effort}"])
        argv.append(prompt_for(case, workspace))
        append_event(event_log, {"kind": "command", "name": "codex.exec", "argv": [str(value) for value in argv[:4]]})

        timeout_seconds = int(os.environ.get("PMAI_CODEX_TIMEOUT_SECONDS", "600"))
        child_env = os.environ.copy()
        child_env["PMAI_HOME"] = str(framework_root)
        case_skills = case.get("skills") if isinstance(case.get("skills"), list) else []
        if "mockup" in case_skills:
            # The external CLI has no interactive gstack browser channel. Let the
            # mockup skill take its documented HTML fallback instead of hanging
            # inside a daemon-backed design/browse command.
            path_entries = child_env.get("PATH", "").split(os.pathsep)
            child_env["PATH"] = os.pathsep.join(
                entry
                for entry in path_entries
                if all(token not in entry.lower() for token in ("/.agents/", "/.codex/", "/.claude/"))
            )
            child_env["GSTACK_BROWSE_BIN"] = "/nonexistent/pmai-browse"
            child_env["GSTACK_DESIGN_BIN"] = "/nonexistent/pmai-design"
        state_home_raw = harness.get("state_home")
        if isinstance(state_home_raw, str) and state_home_raw.strip():
            child_env["PMAI_STATE_HOME"] = str(Path(state_home_raw).expanduser().resolve())
        context_pack = write_context_pack(case, workspace)
        child_env["PMAI_SESSION_CONTEXT"] = str(context_pack)
        # Rebuild the prompt after the pack path is known so the model can use it.
        argv[-1] = prompt_for(case, workspace)
        failure_reason = ""
        transport_warning = ""
        try:
            completed = run_streaming(
                argv,
                cwd=workspace,
                env=child_env,
                timeout_seconds=timeout_seconds,
                event_log=event_log,
            )
            parsed = parse_events(completed["stdout"])
            if completed["timed_out"]:
                failure_reason = f"Codex timeout after {timeout_seconds}s"
            elif completed["returncode"] != 0:
                failure_reason = parsed["errors"][-1] if parsed["errors"] else f"Codex exit {completed['returncode']}"
                stderr = completed["stderr"].strip()
                if stderr:
                    failure_reason = f"{failure_reason}; stderr: {stderr[-2000:]}"
                if is_recoverable_completed_stream_failure(failure_reason, parsed):
                    transport_warning = failure_reason
                    failure_reason = ""
            elif parsed["errors"]:
                failure_reason = parsed["errors"][-1]
        except OSError as exc:
            parsed = {"transcript": [], "tool_calls": [], "errors": [], "diagnostics": [], "token_usage": None, "thread_id": "", "model": "", "eval_result": None}
            failure_reason = f"Codex command failed: {exc}"

        ended_at = iso_now()
        duration_ms = int((time.monotonic() - started) * 1000)
        if failure_reason:
            append_event(event_log, {"kind": "lifecycle", "value": "failed", "reason": failure_reason[:500]})
        else:
            append_event(event_log, {"kind": "lifecycle", "value": "completed"})
        if transport_warning:
            parsed["diagnostics"].append(f"recoverable transport warning: {transport_warning[:1000]}")

        runtime = {
            "started_at": started_at,
            "ended_at": ended_at,
            "duration_ms": duration_ms,
            "token_usage": (
                {"status": "reported", **parsed["token_usage"]}
                if parsed["token_usage"] is not None
                else {"status": "unavailable", "reason": "Codex did not emit a final token event"}
            ),
            "cost": cost_from_tokens(parsed["token_usage"]),
            "failure": (
                {"status": "error", "reason": failure_reason[:1000]}
                if failure_reason
                else {"status": "none"}
            ),
        }
        if transport_warning:
            runtime["transport"] = {"status": "warning", "reason": transport_warning[:1000]}
        success = not failure_reason
        claimed = parsed.get("eval_result") if isinstance(parsed.get("eval_result"), dict) else {}
        observations = claimed.get("observations", [])
        if not isinstance(observations, list):
            observations = claimed.get("actions", [])
        if not isinstance(observations, list):
            observations = []
        lifecycle = claimed.get("lifecycle", claimed.get("claimed_lifecycle", []))
        if not isinstance(lifecycle, list):
            lifecycle = []
        stopping_point = claimed.get("stopping_point", claimed.get("claimed_stopping_point", ""))
        if not isinstance(stopping_point, str):
            stopping_point = ""
        result = {
            "case_id": case["id"],
            "evaluation_id": evaluation_id,
            "provenance": {
                "host": "codex-cli",
                "model": parsed["model"] or os.environ.get("PMAI_CODEX_MODEL", "unknown"),
                "run_id": parsed["thread_id"] or f"codex-{evaluation_id}",
                "framework_revision": framework_revision,
                "consumer_revision": consumer_revision,
            },
            "transcript": parsed["transcript"] or ([failure_reason] if failure_reason else ["Codex returned no assistant message"]),
            "tool_calls": parsed["tool_calls"],
            "file_diff": {},
            "lifecycle": lifecycle if success else [],
            "stopping_point": stopping_point if success else "runner_failed",
            "elapsed_ms": duration_ms,
            "observations": observations if success else ["runner_failed"],
            "claims_trust": "unverified",
            "diagnostics": parsed["diagnostics"],
            "runtime": runtime,
            "status": "pass" if success else "failed",
        }
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except (KeyError, TypeError, ValueError, RuntimeError) as exc:
        print(f"codex runner error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
