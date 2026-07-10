#!/usr/bin/env python3
"""Deterministic fake runner/judge for skill-eval contract tests."""

from __future__ import annotations

import json
import sys


payload = json.load(sys.stdin)
case = payload["case"]
if "result" in payload:
    print(json.dumps({"pass": True, "reason": "deterministic fixture"}))
else:
    expected = case["expected"]
    print(
        json.dumps(
            {
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
