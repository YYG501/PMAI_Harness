#!/usr/bin/env python3
"""Read-only deterministic Judge for the Session Eval JSON protocol.

This process never writes the workspace. It checks the frozen evidence manifest
and the case rubric, while ``skill-eval.py`` remains the final hard-gate owner.
"""

from __future__ import annotations

import hashlib
import json
import sys
from typing import Any


def canonical(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        case = payload["case"]
        result = payload["result"]
        manifest = payload.get("evidence_manifest")
        evaluation_id = str(payload["evaluation_id"])
        issues: list[str] = []

        if not isinstance(manifest, dict):
            issues.append("evidence manifest missing")
        else:
            core = {key: value for key, value in manifest.items() if key != "digest"}
            if manifest.get("digest") != digest(core):
                issues.append("evidence manifest digest mismatch")
            if manifest.get("evaluation_id") != evaluation_id:
                issues.append("evidence manifest evaluation mismatch")
            evidence = manifest.get("independent_evidence")
            if not isinstance(evidence, dict):
                issues.append("independent evidence missing")
            else:
                if (
                    evidence.get("baseline_clean") is not True
                    and evidence.get("allow_initial_dirty") is not True
                ):
                    issues.append("baseline is not clean")
                if evidence.get("missing_expected_paths"):
                    issues.append(f"expected changes missing: {evidence['missing_expected_paths']}")
                if evidence.get("protected_violations"):
                    issues.append(f"protected paths changed: {evidence['protected_violations']}")
                if evidence.get("unchanged_violations"):
                    issues.append(f"expected unchanged paths changed: {evidence['unchanged_violations']}")
                event_log = evidence.get("event_log")
                required_kinds = case.get("harness", {}).get("required_event_kinds", [])
                observed_kinds = set(event_log.get("kinds", [])) if isinstance(event_log, dict) else set()
                missing_kinds = sorted(set(required_kinds) - observed_kinds)
                if missing_kinds:
                    issues.append(f"event kinds missing: {missing_kinds}")
                if evidence.get("framework_revision") != result.get("provenance", {}).get("framework_revision"):
                    issues.append("framework revision is not bound to runner provenance")

        passed = not issues
        output = {
            "case_id": case["id"],
            "evaluation_id": evaluation_id,
            "pass": passed,
            "reason": "independent deterministic evidence review" if passed else "; ".join(issues),
            "assessment_type": "evidence-only",
            "provenance": {
                "host": "pmai-readonly-judge",
                "model": "deterministic-rubric-v1",
                "run_id": f"judge-{evaluation_id}",
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
                "runtime",
                "framework_revision",
                "consumer_revision",
            ],
            "evidence_digest": manifest.get("digest") if isinstance(manifest, dict) else "",
        }
        print(json.dumps(output, ensure_ascii=False))
        return 0
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"judge error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
