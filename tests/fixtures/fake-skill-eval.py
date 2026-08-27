#!/usr/bin/env python3
"""Deterministic fake runner/judge for skill-eval contract tests."""

from __future__ import annotations

import json
import sys
from pathlib import Path


payload = json.load(sys.stdin)
case = payload["case"]
evaluation_id = payload["evaluation_id"]
if "result" in payload:
    runner_run_id = payload["result"]["provenance"]["run_id"]
    judge_run_id = (
        runner_run_id
        if "--reuse-run-id" in sys.argv
        else f"fixture-judge-{evaluation_id}"
    )
    print(
        json.dumps(
            {
                "case_id": case["id"],
                "evaluation_id": evaluation_id,
                "pass": True,
                "reason": "deterministic fixture",
                "provenance": {
                    "host": "fixture",
                    "model": "fixture-judge",
                    "run_id": judge_run_id,
                },
                "reviewed_evidence": [
                    "transcript",
                    "tool_calls",
                    "file_diff",
                    "lifecycle",
                    "stopping_point",
                    "observations",
                    "independent_evidence",
                    "manifest",
                    "digest",
                    "event_log",
                ],
                "evidence_digest": (
                    "tampered-digest"
                    if "--tamper-digest" in sys.argv
                    else payload.get("evidence_manifest", {}).get("digest")
                ),
            }
        )
    )
else:
    harness = payload.get("case", {}).get("harness", {})
    workspace = harness.get("workspace")
    event_log = harness.get("event_log")
    if event_log:
        Path(event_log).write_text(
            "\n".join(
                json.dumps(event, ensure_ascii=False)
                for event in [
                    {"kind": "lifecycle", "value": "iterating"},
                    {"kind": "tool", "name": "fixture.write"},
                    {"kind": "command", "name": "git diff"},
                ]
            )
            + "\n",
            encoding="utf-8",
        )
    if workspace and "--no-change" not in sys.argv:
        if "--touch-protected" in sys.argv:
            target = "docs/modules/change-confirmation/spec.md"
        elif "--touch-unchanged" in sys.argv:
            target = "PRODUCT-STATE.md"
        elif case.get("id") == "readonly-session":
            target = None
        else:
            target = "PRODUCT-STATE.md"
        if target is not None:
            target_path = Path(workspace) / target
            target_path.parent.mkdir(parents=True, exist_ok=True)
            previous = target_path.read_text(encoding="utf-8") if target_path.exists() else ""
            target_path.write_text(previous + "\n定稿后现状已同步。\n", encoding="utf-8")
    print(
        json.dumps(
            {
                "case_id": case["id"],
                "evaluation_id": evaluation_id,
                "provenance": {
                    "host": "fixture",
                    "model": "fixture-runner",
                    "run_id": f"fixture-runner-{evaluation_id}",
                },
                "transcript": ["fixture transcript"],
                "tool_calls": [],
                "file_diff": [],
                "lifecycle": [],
                "stopping_point": "unreported",
                "elapsed_ms": 1,
                "observations": [],
                "claims_trust": "unverified",
            }
        )
    )
