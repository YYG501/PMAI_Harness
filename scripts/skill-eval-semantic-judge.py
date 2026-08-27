#!/usr/bin/env python3
"""Run a read-only semantic Judge for one Session Eval result.

The model Runner never receives this payload. This process receives the private
case rubric and the frozen evidence after the Runner exits, and returns a
structured assessment. It never opens or writes the Runner workspace.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


RESULT_MARKER = re.compile(r"PMAI_SEMANTIC_JUDGE_RESULT:\s*(\{.*\})")


def compact_json(value: Any, limit: int = 180_000) -> str:
    text = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2)
    if len(text) <= limit:
        return text
    return text[:limit] + "\n...[evidence truncated by semantic Judge adapter]"


def judge_prompt(payload: dict[str, Any]) -> str:
    case = payload["case"]
    result = payload["result"]
    manifest = payload.get("evidence_manifest")
    expected = case.get("expected", {})
    forbidden = case.get("forbidden", {})
    rubric = case.get("judge", {}).get("rubric", [])
    evidence = {
        "case_id": case.get("id"),
        "pm_intent": case.get("input", {}),
        "rubric": rubric,
        "expected_behaviors": expected.get("behaviors", []),
        "expected_observations": expected.get("observations", []),
        "expected_lifecycle": expected.get("lifecycle_order", []),
        "expected_stopping_point": expected.get("stopping_point"),
        "forbidden_behaviors": forbidden.get("behaviors", []),
        "forbidden_observations": forbidden.get("observations", []),
        "rubric_criteria_must_be_copied_verbatim": rubric,
        "runner_claims_are_untrusted": True,
        "runner_result": result,
        "independent_evidence_manifest": manifest,
    }
    return (
        "You are the independent semantic Judge for a PMAI Session Eval.\n"
        "Judge only the frozen evidence below. Do not modify files, do not call tools, "
        "and do not trust the Runner's claims without matching transcript, tool, Git, "
        "lifecycle, or file evidence.\n\n"
        "Runner machine-readable observations and claimed fields are untrusted diagnostics, "
        "not capability gates. Do not lower a criterion merely because observations are empty, "
        "and do not require internal audit fields such as semantic_checks or judge_binding "
        "unless the hidden rubric explicitly makes them part of the product behavior. "
        "Score the behavior from transcript, tool calls, file diff, lifecycle and independent "
        "evidence; report missing proof only when those sources cannot establish the criterion.\n\n"
        "Score every rubric criterion exactly 0, 1, or 2:\n"
        "- 2 = clearly satisfied by the evidence\n"
        "- 1 = partially satisfied or evidence is incomplete\n"
        "- 0 = not satisfied or contradicted by the evidence\n"
        "The only allowed criterion names are the exact strings in rubric_criteria_must_be_copied_verbatim. "
        "Return exactly one score for each of those criteria, in the same order. Do not score expected_behaviors, "
        "expected_observations, forbidden_behaviors, or any other field; those are background context only.\n"
        "Set evidence_digest to the exact string in independent_evidence_manifest.digest, copied byte-for-byte; "
        "never replace it with a summary or explanation.\n"
        "The framework checkout may intentionally be dirty because the candidate changes are under test; do not "
        "penalize framework_clean=false or unrelated harness metadata unless a rubric criterion explicitly requires it.\n"
        "Rubrics may describe conditional behavior. When the case context explicitly says a capability is unavailable "
        "and the expected behavior is to record a blocked/limited result without fabricating a pass, that explicit "
        "blocked result satisfies the criterion; do not require the unavailable artifact. When a criterion explicitly "
        "distinguishes the current session from external builder profiles, listing the current-session option is "
        "compliant and must not be scored as offering the current host as an external builder.\n"
        "The overall pass value must be true only when every criterion scores 2.\n"
        "A failed or missing machine contract is a finding even if the final prose sounds good.\n\n"
        "End with exactly one JSON line in this form:\n"
        'PMAI_SEMANTIC_JUDGE_RESULT: {"pass":true,"reason":"...",'
        '"criterion_scores":[{"criterion":"...","score":2,"reason":"..."}],'
        '"findings":[],"root_causes":[],"reviewed_evidence":["transcript",'
        '"tool_calls","file_diff","independent_evidence","manifest","digest"],'
        '"evidence_digest":"..."}\n\n'
        + compact_json(evidence)
    )


def parse_output(raw: str) -> tuple[str, dict[str, Any] | None]:
    thread_id = ""
    candidate: dict[str, Any] | None = None
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "thread.started":
            thread_id = str(event.get("thread_id") or "").strip()
        item = event.get("item")
        if not isinstance(item, dict) or item.get("type") != "agent_message":
            continue
        text = item.get("text")
        if not isinstance(text, str):
            continue
        match = RESULT_MARKER.search(text)
        if not match:
            continue
        try:
            parsed = json.loads(match.group(1))
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            candidate = parsed
    return thread_id, candidate


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        evaluation_id = str(payload["evaluation_id"])
        case = payload["case"]
        result = payload["result"]
        manifest = payload.get("evidence_manifest")
        if not isinstance(case, dict) or not isinstance(result, dict):
            raise ValueError("semantic Judge payload 缺少 case/result")
        with tempfile.TemporaryDirectory(prefix="pmai-semantic-judge-") as temp_dir:
            command = shlex.split(os.environ.get("PMAI_JUDGE_CODEX_COMMAND", "codex"))
            if not command:
                raise ValueError("PMAI_JUDGE_CODEX_COMMAND 为空")
            argv = [
                *command,
                "exec",
                "--approve-for-me",
                "--json",
                "--ephemeral",
                "--cd",
                str(Path(temp_dir).resolve()),
                "--skip-git-repo-check",
                "--ignore-rules",
            ]
            if os.environ.get("PMAI_CODEX_IGNORE_USER_CONFIG") == "1":
                argv.append("--ignore-user-config")
            reasoning_effort = os.environ.get("PMAI_JUDGE_REASONING_EFFORT", "medium").strip()
            if reasoning_effort:
                argv.extend(["-c", f"model_reasoning_effort={reasoning_effort}"])
            argv.append(judge_prompt(payload))
            timeout_seconds = int(os.environ.get("PMAI_JUDGE_TIMEOUT_SECONDS", "600"))
            completed = subprocess.run(
                argv,
                cwd=temp_dir,
                capture_output=True,
                text=True,
                timeout=timeout_seconds,
                check=False,
            )
        thread_id, candidate = parse_output(completed.stdout)
        if completed.returncode != 0:
            detail = completed.stderr.strip()[-2000:]
            raise RuntimeError(f"semantic Judge Codex exit {completed.returncode}: {detail}")
        if candidate is None:
            raise RuntimeError("semantic Judge did not emit a valid PMAI_SEMANTIC_JUDGE_RESULT marker")
        candidate["case_id"] = case["id"]
        candidate["evaluation_id"] = evaluation_id
        candidate["assessment_type"] = "semantic-llm-v1"
        candidate["provenance"] = {
            "host": "codex-semantic-judge",
            "model": os.environ.get("PMAI_JUDGE_MODEL", "unknown"),
            "run_id": thread_id or f"semantic-judge-{evaluation_id}",
        }
        print(json.dumps(candidate, ensure_ascii=False))
        return 0
    except (KeyError, TypeError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
        print(f"semantic Judge error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
