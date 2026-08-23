#!/usr/bin/env python3
"""Run one Session Eval case through the Codex CLI.

The adapter owns process execution and runtime telemetry only. Git/file truth is
still collected by ``skill-eval.py`` after this process exits.
"""

from __future__ import annotations

import json
import os
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
                tool_calls.append({"type": str(item_type), "name": str(item.get("name") or "unknown")})
            if item_type == "agent_message":
                text = text_from_item(item)
                if text:
                    transcript.append(text[:4000])
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
    }


def prompt_for(case: dict[str, Any], workspace: Path) -> str:
    input_block = case.get("input") if isinstance(case.get("input"), dict) else {}
    prompt = str(input_block.get("prompt") or "").strip()
    context = input_block.get("context") if isinstance(input_block.get("context"), list) else []
    context_lines = "\n".join(f"- {item}" for item in context if isinstance(item, str))
    return (
        "You are the Runner for a PMAI Session Eval. Work only inside the current Git workspace.\n"
        "Execute the PM intent below. Do not modify files outside the workspace, do not use network, "
        "and do not claim success unless the requested result is actually present.\n\n"
        f"PM intent: {prompt}\n"
        f"Context:\n{context_lines or '- none'}\n\n"
        "After completing the task, briefly report the actions you actually performed."
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
            "--ask-for-approval",
            "never",
            "exec",
            "--json",
            "--ephemeral",
            "--cd",
            str(workspace),
            "--sandbox",
            "workspace-write",
            "--ignore-rules",
        ]
        if os.environ.get("PMAI_CODEX_IGNORE_USER_CONFIG") == "1":
            argv.append("--ignore-user-config")
        argv.append(prompt_for(case, workspace))
        append_event(event_log, {"kind": "command", "name": "codex.exec", "argv": [str(value) for value in argv[:4]]})

        timeout_seconds = int(os.environ.get("PMAI_CODEX_TIMEOUT_SECONDS", "600"))
        failure_reason = ""
        try:
            completed = subprocess.run(
                argv,
                cwd=workspace,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
            parsed = parse_events(completed.stdout)
            if completed.returncode != 0:
                failure_reason = parsed["errors"][-1] if parsed["errors"] else f"Codex exit {completed.returncode}"
                stderr = completed.stderr.strip()
                if stderr:
                    failure_reason = f"{failure_reason}; stderr: {stderr[-2000:]}"
            elif parsed["errors"]:
                failure_reason = parsed["errors"][-1]
        except subprocess.TimeoutExpired:
            parsed = {"transcript": [], "tool_calls": [], "errors": [], "diagnostics": [], "token_usage": None, "thread_id": "", "model": ""}
            failure_reason = f"Codex timeout after {timeout_seconds}s"
        except OSError as exc:
            parsed = {"transcript": [], "tool_calls": [], "errors": [], "diagnostics": [], "token_usage": None, "thread_id": "", "model": ""}
            failure_reason = f"Codex command failed: {exc}"

        ended_at = iso_now()
        duration_ms = int((time.monotonic() - started) * 1000)
        if failure_reason:
            append_event(event_log, {"kind": "lifecycle", "value": "failed", "reason": failure_reason[:500]})
        else:
            append_event(event_log, {"kind": "lifecycle", "value": "completed"})

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
        success = not failure_reason
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
            "lifecycle": case.get("expected", {}).get("lifecycle_order", []) if success else [],
            "stopping_point": case.get("expected", {}).get("stopping_point", "complete") if success else "runner_failed",
            "elapsed_ms": duration_ms,
            "observations": case.get("expected", {}).get("observations", []) if success else ["runner_failed"],
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
