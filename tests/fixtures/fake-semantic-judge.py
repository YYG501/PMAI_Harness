#!/usr/bin/env python3
"""Deterministic semantic-judge double for protocol tests."""

from __future__ import annotations

import json
import sys


payload = json.load(sys.stdin)
case = payload["case"]
evaluation_id = payload["evaluation_id"]
rubric = case["judge"]["rubric"]
manifest = payload.get("evidence_manifest") or {}
print(
    json.dumps(
        {
            "case_id": case["id"],
            "evaluation_id": evaluation_id,
            "assessment_type": "semantic-llm-v1",
            "pass": True,
            "reason": "deterministic semantic fixture",
            "criterion_scores": [
                {"criterion": criterion, "score": 2, "reason": "fixture evidence"}
                for criterion in rubric
            ],
            "findings": [],
            "root_causes": [],
            "provenance": {
                "host": "semantic-judge-fixture",
                "model": "fixture-semantic-judge",
                "run_id": f"semantic-fixture-{evaluation_id}",
            },
            "reviewed_evidence": [
                "transcript",
                "tool_calls",
                "file_diff",
                "independent_evidence",
                "manifest",
                "digest",
            ],
            "evidence_digest": manifest.get("digest", ""),
        },
        ensure_ascii=False,
    )
)
