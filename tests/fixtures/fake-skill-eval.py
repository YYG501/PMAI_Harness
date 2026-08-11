#!/usr/bin/env python3
"""Deterministic fake runner/judge for skill-eval contract tests."""

from __future__ import annotations

import json
import sys


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
                ],
            }
        )
    )
else:
    expected = case["expected"]
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
                "lifecycle": expected.get("lifecycle_order", []),
                "stopping_point": expected.get("stopping_point", "complete"),
                "elapsed_ms": 1,
                "observations": expected.get("observations", []),
            }
        )
    )
