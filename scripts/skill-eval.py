#!/usr/bin/env python3
"""Validate and run PMAI skill regression cases.

Static cases run without an LLM. Session cases use an optional external runner
and judge with a JSON-over-stdin/stdout protocol. Missing external capabilities
are always reported as SKIP, or become failures when the corresponding
--require-* flag is used.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
VALID_LAYERS = {"static", "session"}
VALID_ASSERTIONS = {"path_exists", "file_contains", "file_not_contains"}
CASE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
REQUIRED_RESULT_FIELDS = {
    "case_id",
    "evaluation_id",
    "provenance",
    "transcript",
    "tool_calls",
    "file_diff",
    "lifecycle",
    "stopping_point",
    "elapsed_ms",
    "observations",
}
REQUIRED_PROVENANCE_FIELDS = {"host", "model", "run_id"}
REQUIRED_JUDGE_EVIDENCE = {
    "transcript",
    "tool_calls",
    "file_diff",
    "lifecycle",
    "stopping_point",
    "observations",
}


class EvalError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise EvalError(f"文件不存在: {path}") from exc
    except json.JSONDecodeError as exc:
        raise EvalError(f"JSON 不合法: {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise EvalError(f"JSON 顶层必须是对象: {path}")
    return value


def require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EvalError(f"{label} 必须是非空字符串")
    return value


def require_string_list(value: Any, label: str, *, allow_empty: bool = False) -> list[str]:
    if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
        raise EvalError(f"{label} 必须是字符串数组")
    if not allow_empty and not value:
        raise EvalError(f"{label} 不能为空")
    return value


def safe_repo_path(repo_root: Path, raw: Any, label: str) -> Path:
    value = require_string(raw, label)
    candidate = Path(value)
    if candidate.is_absolute() or ".." in candidate.parts:
        raise EvalError(f"{label} 必须是仓内相对路径: {value}")
    resolved = (repo_root / candidate).resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError as exc:
        raise EvalError(f"{label} 越出仓库: {value}") from exc
    return resolved


def validate_case(case: dict[str, Any], path: Path, repo_root: Path) -> str:
    if case.get("schema_version") != SCHEMA_VERSION:
        raise EvalError(f"{path}: schema_version 必须为 {SCHEMA_VERSION}")
    case_id = require_string(case.get("id"), f"{path}: id")
    if not CASE_ID_RE.fullmatch(case_id):
        raise EvalError(f"{path}: id 只能使用小写字母、数字和连字符")
    if path.stem != case_id:
        raise EvalError(f"{path}: 文件名必须与 id 一致")
    require_string(case.get("title"), f"{case_id}: title")
    layer = require_string(case.get("layer"), f"{case_id}: layer")
    if layer not in VALID_LAYERS:
        raise EvalError(f"{case_id}: layer 必须是 static 或 session")
    require_string_list(case.get("skills"), f"{case_id}: skills")

    input_block = case.get("input")
    if not isinstance(input_block, dict):
        raise EvalError(f"{case_id}: input 必须是对象")
    require_string(input_block.get("prompt"), f"{case_id}: input.prompt")
    require_string_list(input_block.get("context", []), f"{case_id}: input.context", allow_empty=True)

    expected = case.get("expected")
    forbidden = case.get("forbidden")
    if not isinstance(expected, dict) or not isinstance(forbidden, dict):
        raise EvalError(f"{case_id}: expected / forbidden 必须是对象")
    require_string_list(expected.get("behaviors"), f"{case_id}: expected.behaviors")
    require_string_list(
        expected.get("observations"), f"{case_id}: expected.observations", allow_empty=layer == "static"
    )
    require_string_list(
        forbidden.get("behaviors"), f"{case_id}: forbidden.behaviors", allow_empty=True
    )
    require_string_list(
        forbidden.get("observations"), f"{case_id}: forbidden.observations", allow_empty=True
    )
    require_string_list(
        expected.get("lifecycle_order", []), f"{case_id}: expected.lifecycle_order", allow_empty=True
    )
    if "stopping_point" in expected:
        require_string(expected.get("stopping_point"), f"{case_id}: expected.stopping_point")

    assertions = case.get("assertions", [])
    if not isinstance(assertions, list):
        raise EvalError(f"{case_id}: assertions 必须是数组")
    if layer == "static" and not assertions:
        raise EvalError(f"{case_id}: static case 至少需要一个 assertion")
    for index, assertion in enumerate(assertions, 1):
        if not isinstance(assertion, dict):
            raise EvalError(f"{case_id}: assertion {index} 必须是对象")
        kind = require_string(assertion.get("type"), f"{case_id}: assertion {index}.type")
        if kind not in VALID_ASSERTIONS:
            raise EvalError(f"{case_id}: 不支持 assertion 类型 {kind}")
        safe_repo_path(repo_root, assertion.get("path"), f"{case_id}: assertion {index}.path")
        if kind != "path_exists":
            require_string(assertion.get("value"), f"{case_id}: assertion {index}.value")

    if layer == "session":
        source = case.get("source")
        if not isinstance(source, dict):
            raise EvalError(f"{case_id}: session case 必须有 source")
        require_string(source.get("session_id"), f"{case_id}: source.session_id")
        evidence = source.get("evidence")
        if not isinstance(evidence, list) or not evidence:
            raise EvalError(f"{case_id}: source.evidence 不能为空")
        for index, item in enumerate(evidence, 1):
            if not isinstance(item, dict):
                raise EvalError(f"{case_id}: evidence {index} 必须是对象")
            if not isinstance(item.get("turn"), int) or item["turn"] < 0:
                raise EvalError(f"{case_id}: evidence {index}.turn 必须是非负整数")
            require_string(item.get("excerpt"), f"{case_id}: evidence {index}.excerpt")
        judge = case.get("judge")
        if not isinstance(judge, dict) or judge.get("enabled") is not True:
            raise EvalError(f"{case_id}: session case 必须启用 judge")
        require_string_list(judge.get("rubric"), f"{case_id}: judge.rubric")

    return case_id


def load_cases(cases_dir: Path, repo_root: Path) -> list[dict[str, Any]]:
    paths = sorted(cases_dir.glob("*.json"))
    if not paths:
        raise EvalError(f"没有评测案例: {cases_dir}")
    cases: list[dict[str, Any]] = []
    seen: set[str] = set()
    for path in paths:
        case = read_json(path)
        case_id = validate_case(case, path, repo_root)
        if case_id in seen:
            raise EvalError(f"重复 case id: {case_id}")
        seen.add(case_id)
        case["_path"] = str(path)
        cases.append(case)
    return cases


def validate_touchfiles(
    path: Path, cases: list[dict[str, Any]], repo_root: Path
) -> dict[str, list[str]]:
    payload = read_json(path)
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise EvalError(f"{path}: schema_version 必须为 {SCHEMA_VERSION}")
    mapping = payload.get("cases")
    if not isinstance(mapping, dict):
        raise EvalError(f"{path}: cases 必须是对象")
    case_ids = {case["id"] for case in cases}
    mapped_ids = set(mapping)
    if mapped_ids != case_ids:
        missing = sorted(case_ids - mapped_ids)
        extra = sorted(mapped_ids - case_ids)
        raise EvalError(f"touchfiles case 不一致: missing={missing}, extra={extra}")
    validated: dict[str, list[str]] = {}
    for case_id, paths in mapping.items():
        values = require_string_list(paths, f"touchfiles.{case_id}")
        for raw in values:
            candidate = safe_repo_path(repo_root, raw, f"touchfiles.{case_id}")
            if not candidate.exists():
                raise EvalError(f"touchfiles.{case_id} 指向不存在路径: {raw}")
        validated[case_id] = values
    return validated


def run_static_assertion(assertion: dict[str, Any], repo_root: Path) -> tuple[bool, str]:
    kind = assertion["type"]
    raw_path = assertion["path"]
    path = safe_repo_path(repo_root, raw_path, f"assertion path {raw_path}")
    if kind == "path_exists":
        return path.exists(), f"path_exists {raw_path}"
    if not path.is_file():
        return False, f"文件不存在: {raw_path}"
    content = path.read_text(encoding="utf-8")
    value = assertion["value"]
    if kind == "file_contains":
        return value in content, f"file_contains {raw_path}: {value}"
    return value not in content, f"file_not_contains {raw_path}: {value}"


def lifecycle_contains(actual: list[Any], expected: list[str]) -> bool:
    cursor = 0
    for value in actual:
        if cursor < len(expected) and value == expected[cursor]:
            cursor += 1
    return cursor == len(expected)


def run_external(command: str, payload: dict[str, Any], timeout: int, label: str) -> dict[str, Any]:
    argv = shlex.split(command)
    if not argv:
        raise EvalError(f"{label} 命令为空")
    try:
        completed = subprocess.run(
            argv,
            input=json.dumps(payload, ensure_ascii=False),
            text=True,
            capture_output=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise EvalError(f"{label} 无法执行: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise EvalError(f"{label} 退出 {completed.returncode}: {detail}")
    try:
        value = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise EvalError(f"{label} 未返回合法 JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise EvalError(f"{label} 返回值必须是 JSON 对象")
    return value


def validate_provenance(value: Any, label: str) -> list[str]:
    if not isinstance(value, dict):
        return [f"{label} 必须是对象"]
    problems = []
    for field in sorted(REQUIRED_PROVENANCE_FIELDS):
        if not isinstance(value.get(field), str) or not value[field].strip():
            problems.append(f"{label}.{field} 必须是非空字符串")
    return problems


def validate_runner_result(
    case: dict[str, Any], result: dict[str, Any], evaluation_id: str
) -> list[str]:
    problems: list[str] = []
    missing = sorted(REQUIRED_RESULT_FIELDS - set(result))
    if missing:
        problems.append(f"runner 结果缺字段: {missing}")
        return problems
    if result["case_id"] != case["id"]:
        problems.append("runner case_id 与当前案例不一致")
    if result["evaluation_id"] != evaluation_id:
        problems.append("runner evaluation_id 与当前执行不一致")
    problems.extend(validate_provenance(result["provenance"], "runner provenance"))
    if not isinstance(result["transcript"], (str, list)) or not result["transcript"]:
        problems.append("transcript 必须非空")
    if not isinstance(result["tool_calls"], list):
        problems.append("tool_calls 必须是数组")
    if not isinstance(result["file_diff"], (str, list, dict)):
        problems.append("file_diff 必须是字符串、数组或对象")
    if not isinstance(result["lifecycle"], list):
        problems.append("lifecycle 必须是数组")
    if not isinstance(result["stopping_point"], str) or not result["stopping_point"]:
        problems.append("stopping_point 必须是非空字符串")
    if not isinstance(result["elapsed_ms"], (int, float)) or result["elapsed_ms"] < 0:
        problems.append("elapsed_ms 必须是非负数")
    observations = result["observations"]
    if not isinstance(observations, list) or any(not isinstance(item, str) for item in observations):
        problems.append("observations 必须是字符串数组")
        return problems

    expected = case["expected"]
    forbidden = case["forbidden"]
    missing_observations = sorted(set(expected["observations"]) - set(observations))
    forbidden_observations = sorted(set(forbidden["observations"]) & set(observations))
    if missing_observations:
        problems.append(f"缺少预期 observations: {missing_observations}")
    if forbidden_observations:
        problems.append(f"命中禁止 observations: {forbidden_observations}")
    expected_lifecycle = expected.get("lifecycle_order", [])
    if expected_lifecycle and not lifecycle_contains(result["lifecycle"], expected_lifecycle):
        problems.append(
            f"lifecycle 顺序不匹配: expected={expected_lifecycle}, actual={result['lifecycle']}"
        )
    stopping_point = expected.get("stopping_point")
    if stopping_point and result["stopping_point"] != stopping_point:
        problems.append(
            f"stopping_point 不匹配: expected={stopping_point}, actual={result['stopping_point']}"
        )
    return problems


def validate_judge_result(
    case: dict[str, Any],
    result: dict[str, Any],
    judge: dict[str, Any],
    evaluation_id: str,
) -> list[str]:
    problems: list[str] = []
    if judge.get("case_id") != case["id"]:
        problems.append("judge case_id 与当前案例不一致")
    if judge.get("evaluation_id") != evaluation_id:
        problems.append("judge evaluation_id 与当前执行不一致")
    if not isinstance(judge.get("pass"), bool):
        problems.append("judge pass 必须是布尔值")
    if not isinstance(judge.get("reason"), str) or not judge["reason"].strip():
        problems.append("judge reason 必须是非空字符串")
    problems.extend(validate_provenance(judge.get("provenance"), "judge provenance"))

    reviewed = judge.get("reviewed_evidence")
    if not isinstance(reviewed, list) or any(not isinstance(item, str) for item in reviewed):
        problems.append("judge reviewed_evidence 必须是字符串数组")
    else:
        missing = sorted(REQUIRED_JUDGE_EVIDENCE - set(reviewed))
        if missing:
            problems.append(f"judge 未声明检查完整 runner 证据: {missing}")

    runner_provenance = result.get("provenance")
    judge_provenance = judge.get("provenance")
    if isinstance(runner_provenance, dict) and isinstance(judge_provenance, dict):
        if runner_provenance.get("run_id") == judge_provenance.get("run_id"):
            problems.append("judge 必须使用独立于 runner 的 run_id")
    if judge.get("pass") is False:
        problems.append(f"judge 未通过: {judge.get('reason', 'no reason')}")
    return problems


def persist_result(results_dir: Path, case: dict[str, Any], result: dict[str, Any], judge: Any) -> None:
    results_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "case_id": case["id"],
        "saved_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "runner_result": result,
        "judge_result": judge,
    }
    (results_dir / f"{case['id']}.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("validate", "static", "session", "all"), default="all")
    parser.add_argument("--cases-dir", default=str(repo_root / "evals" / "cases"))
    parser.add_argument("--touchfiles", default=str(repo_root / "evals" / "touchfiles.json"))
    parser.add_argument("--case", action="append", dest="case_ids", default=[])
    parser.add_argument("--runner-command", default=os.environ.get("PMAI_SKILL_EVAL_RUNNER", ""))
    parser.add_argument("--judge-command", default=os.environ.get("PMAI_SKILL_EVAL_JUDGE", ""))
    parser.add_argument("--require-runner", action="store_true")
    parser.add_argument("--require-judge", action="store_true")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--results-dir")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent
    try:
        cases = load_cases(Path(args.cases_dir).expanduser().resolve(), repo_root)
        validate_touchfiles(Path(args.touchfiles).expanduser().resolve(), cases, repo_root)
    except EvalError as exc:
        print(f"FAIL schema: {exc}")
        return 1

    if args.case_ids:
        requested = set(args.case_ids)
        known = {case["id"] for case in cases}
        unknown = sorted(requested - known)
        if unknown:
            print(f"FAIL unknown cases: {unknown}")
            return 1
        cases = [case for case in cases if case["id"] in requested]

    print(f"PASS schema: {len(cases)} cases + touchfiles")
    if args.mode == "validate":
        return 0

    selected_layers = VALID_LAYERS if args.mode == "all" else {args.mode}
    selected = [case for case in cases if case["layer"] in selected_layers]
    passed = 0
    failed = 0
    skipped = 0
    judge_skipped = 0
    if args.results_dir:
        results_dir = Path(args.results_dir).expanduser().resolve()
    else:
        run_id = datetime.now().strftime("%Y%m%d-%H%M%S")
        results_dir = repo_root / "evals" / "results" / run_id

    for case in selected:
        case_id = case["id"]
        if case["layer"] == "static":
            problems = []
            for assertion in case["assertions"]:
                ok, detail = run_static_assertion(assertion, repo_root)
                if not ok:
                    problems.append(detail)
            if problems:
                failed += 1
                print(f"FAIL {case_id}: {'; '.join(problems)}")
            else:
                passed += 1
                print(f"PASS {case_id}: {len(case['assertions'])} static assertions")
            continue

        if not args.runner_command:
            if args.require_runner:
                failed += 1
                print(f"FAIL {case_id}: session runner 未配置")
            else:
                skipped += 1
                print(f"SKIP {case_id}: session runner 未配置")
            continue

        evaluation_id = uuid.uuid4().hex
        case_payload = {key: value for key, value in case.items() if key != "_path"}
        runner_payload = {
            "schema_version": SCHEMA_VERSION,
            "evaluation_id": evaluation_id,
            "case": case_payload,
        }
        try:
            result = run_external(args.runner_command, runner_payload, args.timeout, f"runner {case_id}")
            problems = validate_runner_result(case, result, evaluation_id)
        except EvalError as exc:
            problems = [str(exc)]
            result = {}

        judge_result: dict[str, Any] | None = None
        if not problems and case.get("judge", {}).get("enabled"):
            if args.judge_command:
                try:
                    judge_result = run_external(
                        args.judge_command,
                        {
                            "schema_version": SCHEMA_VERSION,
                            "evaluation_id": evaluation_id,
                            "case": case_payload,
                            "result": result,
                        },
                        args.timeout,
                        f"judge {case_id}",
                    )
                    problems.extend(
                        validate_judge_result(case, result, judge_result, evaluation_id)
                    )
                except EvalError as exc:
                    problems.append(str(exc))
            elif args.require_judge:
                problems.append("LLM judge 未配置")
            else:
                judge_skipped += 1
                print(f"SKIP judge {case_id}: LLM judge 未配置")
                if result:
                    persist_result(results_dir, case, result, None)
                skipped += 1
                continue

        if result:
            persist_result(results_dir, case, result, judge_result)
        if problems:
            failed += 1
            print(f"FAIL {case_id}: {'; '.join(problems)}")
        else:
            passed += 1
            print(f"PASS {case_id}: runner result + independent judge")

    print(
        f"SUMMARY passed={passed} failed={failed} skipped={skipped} judge_skipped={judge_skipped}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
