#!/usr/bin/env python3
"""Small JSONL Codex CLI double used by the adapter contract test."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def option(name: str) -> str | None:
    try:
        index = sys.argv.index(name)
    except ValueError:
        return None
    return sys.argv[index + 1] if index + 1 < len(sys.argv) else None


workspace = Path(option("--cd") or ".")
if "--skip-git-repo-check" not in sys.argv:
    print("fake runner missing --skip-git-repo-check", file=sys.stderr)
    raise SystemExit(17)
if "--assert-readonly-prompt" in sys.argv:
    prompt = sys.argv[-1]
    required = (
        "protected paths are immutable",
        "expected unchanged paths must remain byte-for-byte unchanged",
        "This case is read-only from the Harness perspective",
    )
    if any(fragment not in prompt for fragment in required):
        print("fake runner missing Harness read-only prompt boundary", file=sys.stderr)
        raise SystemExit(18)
if "--fail-with-stderr" in sys.argv:
    print("fake stderr failure", file=sys.stderr)
    raise SystemExit(7)
target = workspace / "PRODUCT-STATE.md"
target.write_text(target.read_text(encoding="utf-8") + "\n定稿后现状已同步。\n", encoding="utf-8")
print(json.dumps({"type": "thread.started", "thread_id": "fake-codex-thread"}))
print(json.dumps({"type": "item.completed", "item": {"type": "command_execution", "name": "python"}}))
print(json.dumps({
    "type": "item.completed",
    "item": {
        "type": "error",
        "message": "non-fatal skill context diagnostic",
    },
}))
marker = ('PMAI_EVAL_RESULT: {"observations":["acceptance_phrase_recognized","full_checks_run",'
          '"implementation_landed","post_land_docs_synced"],"lifecycle":["iterating",'
          '"final_check","landed","documenting","complete"],"stopping_point":"complete"}')
print(json.dumps({"type": "item.completed", "item": {"type": "agent_message", "text": f"已完成定稿同步。\n{marker}"}}))
if "--legacy-tokens" in sys.argv:
    print(json.dumps({
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": 120,
                    "output_tokens": 30,
                    "total_tokens": 150,
                }
            },
        },
    }))
if "--disconnect-after-result" in sys.argv:
    if "--turn-failed-transport" in sys.argv:
        print(json.dumps({
            "type": "turn.failed",
            "message": "Reconnecting... stream disconnected before completion: Transport error",
        }))
    print("stream disconnected before completion: fake provider warning", file=sys.stderr)
    raise SystemExit(7)
else:
    print(json.dumps({
        "type": "turn.completed",
        "usage": {
            "input_tokens": 120,
            "cached_input_tokens": 80,
            "output_tokens": 30,
            "reasoning_output_tokens": 10,
        },
    }))
