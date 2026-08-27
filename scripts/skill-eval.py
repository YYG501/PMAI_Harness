#!/usr/bin/env python3
"""Validate and run PMAI skill regression cases.

Static cases run without an LLM. Session cases use an optional external runner
and judge with a JSON-over-stdin/stdout protocol. Cases with a ``harness`` block
also run inside a disposable fixture: the Harness independently snapshots Git
and file hashes, then binds the evidence manifest to a content digest. Missing
external capabilities are always reported as SKIP, or become failures when the
corresponding ``--require-*`` flag is used.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
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
REQUIRED_SEMANTIC_EVIDENCE = {
    "transcript",
    "tool_calls",
    "file_diff",
    "independent_evidence",
    "manifest",
    "digest",
}
REQUIRED_MANIFEST_FIELDS = {
    "schema_version",
    "evaluation_id",
    "case_id",
    "case_sha256",
    "runner_result_sha256",
    "independent_evidence",
    "digest",
}
REQUIRED_RUNTIME_FIELDS = {
    "started_at",
    "ended_at",
    "duration_ms",
    "token_usage",
    "cost",
    "failure",
}
VALID_RUNTIME_STATUSES = {"reported", "unavailable"}
VALID_FAILURE_STATUSES = {"none", "error"}
VALID_FIXTURE_STATES = {"preserve", "designing", "ready_to_build", "iterating", "landed"}
RUNNER_HIDDEN_KEYS = {"title", "source", "expected", "forbidden", "judge"}
RUNNER_HIDDEN_HARNESS_KEYS = {
    "fixture",
    "setup",
    "expected_changed_paths",
    "expected_unchanged_paths",
    "protected_paths",
    "required_event_kinds",
    "evidence_paths",
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


def build_runner_case_payload(case_payload: dict[str, Any], harness_context: dict[str, Any]) -> dict[str, Any]:
    """Build the public case view sent to the model runner.

    Expected outcomes, forbidden outcomes, rubrics, source excerpts and harness
    assertions are evaluator-private. The runner must act on the PM request and
    the isolated workspace only; otherwise a session eval can leak its answer.
    """
    public = {
        key: copy.deepcopy(value)
        for key, value in case_payload.items()
        if key not in RUNNER_HIDDEN_KEYS
    }
    harness = public.get("harness")
    if not isinstance(harness, dict):
        harness = {}
    public["harness"] = {
        key: value
        for key, value in harness.items()
        if key not in RUNNER_HIDDEN_HARNESS_KEYS
    }
    public["harness"].update(
        {
            "workspace": str(harness_context["workspace"]),
            "baseline_commit": harness_context["baseline"]["commit"],
            "event_log": str(harness_context["event_log"]),
            "state_home": str(harness_context["state_home"]),
        }
    )
    return public


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
        harness = case.get("harness")
        if harness is not None:
            if not isinstance(harness, dict):
                raise EvalError(f"{case_id}: harness 必须是对象")
            fixture = safe_repo_path(repo_root, harness.get("fixture"), f"{case_id}: harness.fixture")
            if not fixture.is_dir():
                raise EvalError(f"{case_id}: harness.fixture 必须是目录")
            expected_paths = require_string_list(
                harness.get("expected_changed_paths"),
                f"{case_id}: harness.expected_changed_paths",
                allow_empty=True,
            )
            protected_paths = require_string_list(
                harness.get("protected_paths", []),
                f"{case_id}: harness.protected_paths",
                allow_empty=True,
            )
            unchanged_paths = require_string_list(
                harness.get("expected_unchanged_paths", []),
                f"{case_id}: harness.expected_unchanged_paths",
                allow_empty=True,
            )
            required_event_kinds = require_string_list(
                harness.get("required_event_kinds"),
                f"{case_id}: harness.required_event_kinds",
            )
            setup = harness.get("setup", {})
            if not isinstance(setup, dict):
                raise EvalError(f"{case_id}: harness.setup 必须是对象")
            setup_state = setup.get("state", "preserve")
            if setup_state not in VALID_FIXTURE_STATES:
                raise EvalError(
                    f"{case_id}: harness.setup.state 必须是 "
                    + " / ".join(sorted(VALID_FIXTURE_STATES))
                )
            if setup_state != "preserve":
                fixture_relative_path(
                    setup.get("module_dir", "docs/modules/change-confirmation"),
                    f"{case_id}: harness.setup.module_dir",
                )
                fixture_relative_path(
                    setup.get("target_path", "app/confirm_change.py"),
                    f"{case_id}: harness.setup.target_path",
                )
            initial_dirty = setup.get("initial_dirty", [])
            if not isinstance(initial_dirty, list):
                raise EvalError(f"{case_id}: harness.setup.initial_dirty 必须是数组")
            for index, mutation in enumerate(initial_dirty, 1):
                if not isinstance(mutation, dict):
                    raise EvalError(
                        f"{case_id}: harness.setup.initial_dirty[{index}] 必须是对象"
                    )
                fixture_relative_path(
                    mutation.get("path"),
                    f"{case_id}: harness.setup.initial_dirty[{index}].path",
                )
                if set(mutation) - {"path", "append", "content"}:
                    raise EvalError(
                        f"{case_id}: harness.setup.initial_dirty[{index}] 仅支持 path / append / content"
                    )
                if ("append" in mutation) == ("content" in mutation):
                    raise EvalError(
                        f"{case_id}: harness.setup.initial_dirty[{index}] 必须且只能提供 append 或 content"
                    )
                value = mutation.get("append", mutation.get("content"))
                if not isinstance(value, str):
                    raise EvalError(
                        f"{case_id}: harness.setup.initial_dirty[{index}] 内容必须是字符串"
                    )
            memories = setup.get("personal_memories", [])
            if not isinstance(memories, list) or any(not isinstance(item, dict) for item in memories):
                raise EvalError(f"{case_id}: harness.setup.personal_memories 必须是对象数组")
            if not isinstance(setup.get("consumed_gate", False), bool):
                raise EvalError(f"{case_id}: harness.setup.consumed_gate 必须是布尔值")
            for index, raw in enumerate(expected_paths, 1):
                fixture_relative_path(raw, f"{case_id}: expected_changed_paths[{index}]")
            for index, raw in enumerate(protected_paths, 1):
                fixture_relative_path(raw, f"{case_id}: protected_paths[{index}]")
            for index, raw in enumerate(unchanged_paths, 1):
                fixture_relative_path(raw, f"{case_id}: expected_unchanged_paths[{index}]")

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


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_json(value: Any) -> str:
    return sha256_bytes(canonical_json(value).encode("utf-8"))


def run_git(workspace: Path, args: list[str], label: str) -> str:
    try:
        completed = subprocess.run(
            ["git", "-C", str(workspace), *args],
            text=True,
            capture_output=True,
            check=False,
        )
    except OSError as exc:
        raise EvalError(f"{label} 无法执行 git: {exc}") from exc
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise EvalError(f"{label} 退出 {completed.returncode}: {detail}")
    return completed.stdout


def run_checked(
    command: list[str],
    *,
    cwd: Path,
    label: str,
    input_text: str | None = None,
) -> str:
    completed = subprocess.run(
        command,
        cwd=cwd,
        input=input_text,
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        detail = completed.stderr.strip() or completed.stdout.strip() or f"exit {completed.returncode}"
        raise EvalError(f"{label} 失败: {detail}")
    return completed.stdout


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def fixture_setup_commit(workspace: Path, message: str) -> None:
    run_git(workspace, ["add", "--all"], f"fixture setup add ({message})")
    status = run_git(
        workspace,
        ["status", "--porcelain=v1", "--untracked-files=all"],
        f"fixture setup status ({message})",
    )
    if status.strip():
        run_git(workspace, ["commit", "-q", "-m", message], f"fixture setup commit ({message})")


def reset_fixture_to_designing(workspace: Path, module_dir: Path) -> None:
    path = module_dir / ".work-meta.json"
    existing = read_json(path) if path.exists() else {}
    write_json(
        path,
        {
            "id": str(existing.get("id") or f"work-{module_dir.name}-session-eval"),
            "name": str(existing.get("name") or module_dir.name),
            "branch": "main",
            "status": "active",
            "created_at": str(existing.get("created_at") or "2026-08-01T09:00:00+08:00"),
            "source_hash_version": 2,
            "lifecycle_state": "designing",
        },
    )
    fixture_setup_commit(workspace, "fixture: establish designing state")


def create_ready_fixture_state(
    workspace: Path,
    module_dir: Path,
    target_path: str,
    framework_root: Path,
) -> dict[str, Any]:
    reset_fixture_to_designing(workspace, module_dir)
    seed_consumed_gate(workspace, module_dir, framework_root)
    context_path = workspace / ".pm-workflow" / "context" / f"{module_dir.name}.json"
    run_checked(
        [
            sys.executable,
            str(framework_root / "scripts" / "context-pack.py"),
            "--repo-root",
            str(workspace),
            "--module",
            str(module_dir),
            "--output",
            str(context_path),
        ],
        cwd=workspace,
        label="fixture context pack",
    )
    pack = read_json(context_path)
    checkpoint = run_git(workspace, ["rev-parse", "HEAD"], "fixture ready checkpoint").strip()
    run_checked(
        [
            sys.executable,
            str(framework_root / "scripts" / "build-contract.py"),
            "ready",
            str(module_dir),
            "--approved-source-hash",
            str(pack["source_hash"]),
            "--checkpoint-commit",
            checkpoint,
            "--context-pack",
            str(context_path),
            "--target-path",
            target_path,
            "--design-revision",
            "1",
        ],
        cwd=workspace,
        label="fixture ready contract",
    )
    fixture_setup_commit(workspace, "fixture: establish ready handoff")
    return read_json(module_dir / ".work-meta.json")


def create_iterating_fixture_state(
    workspace: Path,
    module_dir: Path,
    target_path: str,
    framework_root: Path,
) -> dict[str, Any]:
    ready = create_ready_fixture_state(workspace, module_dir, target_path, framework_root)
    project = json.loads(
        run_checked(
            [
                sys.executable,
                str(framework_root / "scripts" / "project-definition.py"),
                "show",
                str(workspace),
            ],
            cwd=workspace,
            label="fixture project definition",
        )
    )
    project_type = str((project.get("project") or {}).get("type") or "product")
    entrypoints = (project.get("implementation") or {}).get("entrypoints") or []
    if not isinstance(entrypoints, list) or not entrypoints:
        raise EvalError("fixture setup 的 project.yml 缺 implementation.entrypoints")
    checkpoint = run_git(workspace, ["rev-parse", "HEAD"], "fixture build baseline").strip()
    module_spec = module_dir.resolve().relative_to(workspace.resolve()).joinpath("spec.md").as_posix()
    command = [
        sys.executable,
        str(framework_root / "scripts" / "build-contract.py"),
        "start",
        str(module_dir),
        "--anchor",
        module_spec,
        "--mode",
        "main",
        "--executor",
        "native",
        "--baseline-sha",
        checkpoint,
        "--target-kind",
        project_type,
        "--target-path",
        target_path,
        "--approved-source-hash",
        str(ready["approved_source_hash"]),
        "--iteration-check",
        "tests",
        "--final-check",
        "tests",
        "--final-check",
        "build",
    ]
    for entrypoint in entrypoints:
        command.extend(["--entrypoint", str(entrypoint)])
    if project_type == "prototype":
        command.extend(["--final-check", "prototype-boundary"])
    run_checked(command, cwd=workspace, label="fixture build start")
    fixture_setup_commit(workspace, "fixture: start build")

    target = workspace / target_path
    if not target.is_file():
        raise EvalError(f"fixture setup target 不存在: {target_path}")
    with target.open("a", encoding="utf-8") as handle:
        handle.write("\n# Session Eval implementation baseline.\n")
    fixture_setup_commit(workspace, "fixture: implementation baseline")
    implementation = run_git(workspace, ["rev-parse", "HEAD"], "fixture implementation commit").strip()
    run_checked(
        [
            sys.executable,
            str(framework_root / "scripts" / "build-contract.py"),
            "commit",
            str(module_dir),
            "--implementation-commit",
            implementation,
        ],
        cwd=workspace,
        label="fixture implementation receipt",
    )
    fixture_setup_commit(workspace, "fixture: enter iteration")
    return read_json(module_dir / ".work-meta.json")


def deep_merge(base: dict[str, Any], patch: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def seed_consumed_gate(workspace: Path, module_dir: Path, framework_root: Path) -> None:
    gate_script = framework_root / "scripts" / "decision-gate.py"
    decisions_path = module_dir / "decisions.md"
    original_decisions = decisions_path.read_text(encoding="utf-8")
    decisions_path.write_text("# 决定\n", encoding="utf-8")
    fixture_setup_commit(workspace, "fixture: establish pre-decision baseline")
    opened = json.loads(
        run_checked(
            [
                sys.executable,
                str(gate_script),
                "open",
                str(module_dir),
                "--kind",
                "product-model",
                "--summary",
                "旧问题处理方式",
                "--message",
                "旧问题采用哪个已展示方案？",
                "--option",
                "1=采用方案一",
                "--option",
                "2=采用方案二",
                "--session-id",
                "fixture-old-session",
            ],
            cwd=workspace,
            label="fixture consumed gate open",
        )
    )
    observed = json.loads(
        run_checked(
            [
                sys.executable,
                str(gate_script),
                "observe",
                "--repo-root",
                str(workspace),
                "--message",
                "1",
                "--session-id",
                "fixture-old-session",
                "--message-id",
                "fixture-old-answer",
            ],
            cwd=workspace,
            label="fixture consumed gate observe",
        )
    )
    run_checked(
        [
            sys.executable,
            str(gate_script),
            "answer",
            str(module_dir),
            "--gate-id",
            str(opened["gate_id"]),
            "--event-id",
            str(observed["event_id"]),
        ],
        cwd=workspace,
        label="fixture consumed gate answer",
    )
    run_checked(
        [
            sys.executable,
            str(gate_script),
            "consume",
            str(module_dir),
            "--gate-id",
            str(opened["gate_id"]),
            "--decision-id",
            "D1",
        ],
        cwd=workspace,
        label="fixture consumed gate consume",
    )
    decisions_path.write_text(original_decisions, encoding="utf-8")
    fixture_setup_commit(workspace, "fixture: preserve consumed answer receipt")


def apply_fixture_setup(
    workspace: Path,
    setup: dict[str, Any],
    framework_root: Path,
    temp_root: Path,
) -> tuple[Path, bool]:
    state = str(setup.get("state") or "preserve")
    module_rel = str(setup.get("module_dir") or "docs/modules/change-confirmation")
    target_path = str(setup.get("target_path") or "app/confirm_change.py")
    module_dir = workspace / module_rel
    if state == "designing":
        reset_fixture_to_designing(workspace, module_dir)
    elif state == "ready_to_build":
        create_ready_fixture_state(workspace, module_dir, target_path, framework_root)
    elif state in {"iterating", "landed"}:
        meta = create_iterating_fixture_state(workspace, module_dir, target_path, framework_root)
        if state == "landed":
            build = meta.get("build") if isinstance(meta.get("build"), dict) else {}
            build["lifecycle_state"] = "landed"
            build["docs_status"] = "pending"
            meta.pop("lifecycle_state", None)
            meta["build"] = build
            write_json(module_dir / ".work-meta.json", meta)
            fixture_setup_commit(workspace, "fixture: establish landed state")

    if setup.get("consumed_gate") is True:
        seed_consumed_gate(workspace, module_dir, framework_root)

    meta_patch = setup.get("meta_patch")
    if isinstance(meta_patch, dict):
        meta_path = module_dir / ".work-meta.json"
        write_json(meta_path, deep_merge(read_json(meta_path), meta_patch))
        fixture_setup_commit(workspace, "fixture: apply scenario metadata")

    state_home = temp_root / "state-home"
    for index, memory in enumerate(setup.get("personal_memories", []), 1):
        run_checked(
            [
                sys.executable,
                str(framework_root / "scripts" / "personal-memory.py"),
                "--state-home",
                str(state_home),
                "capture",
                "--stdin",
            ],
            cwd=workspace,
            label=f"fixture personal memory {index}",
            input_text=json.dumps(memory, ensure_ascii=False),
        )

    initial_dirty = setup.get("initial_dirty", [])
    for mutation in initial_dirty:
        target = workspace / str(mutation["path"])
        target.parent.mkdir(parents=True, exist_ok=True)
        if "append" in mutation:
            with target.open("a", encoding="utf-8") as handle:
                handle.write(str(mutation["append"]))
        else:
            target.write_text(str(mutation["content"]), encoding="utf-8")
    return state_home, bool(initial_dirty)


def fixture_relative_path(raw: Any, label: str) -> str:
    value = require_string(raw, label)
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise EvalError(f"{label} 必须是 fixture 内相对路径: {value}")
    return path.as_posix()


def file_hashes(workspace: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for path in sorted(workspace.rglob("*")):
        if ".git" in path.relative_to(workspace).parts:
            continue
        relative = path.relative_to(workspace).as_posix()
        if path.is_symlink():
            values[relative] = f"symlink:{path.readlink()}"
        elif path.is_file():
            values[relative] = sha256_bytes(path.read_bytes())
    return values


def evidence_file_snapshots(workspace: Path, paths: list[str]) -> dict[str, Any]:
    snapshots: dict[str, Any] = {}
    for relative in paths:
        path = workspace / relative
        if path.is_symlink():
            snapshots[relative] = {
                "kind": "symlink",
                "target": str(path.readlink()),
            }
        elif path.is_file():
            raw = path.read_bytes()
            limit = 30_000
            snapshots[relative] = {
                "kind": "file",
                "sha256": sha256_bytes(raw),
                "size": len(raw),
                "content": raw[:limit].decode("utf-8", errors="replace"),
                "truncated": len(raw) > limit,
            }
        else:
            snapshots[relative] = {"kind": "missing"}
    return snapshots


def snapshot_workspace(
    workspace: Path,
    baseline_commit: str | None = None,
    evidence_paths: list[str] | None = None,
) -> dict[str, Any]:
    status = run_git(workspace, ["status", "--porcelain=v1", "--untracked-files=all"], "workspace status")
    commit = run_git(workspace, ["rev-parse", "HEAD"], "workspace commit").strip()
    diff = ""
    if baseline_commit:
        diff = run_git(
            workspace,
            ["diff", "--no-ext-diff", "--binary", baseline_commit, "--"],
            "workspace diff",
        )
    return {
        "commit": commit,
        "status": status,
        "clean": not bool(status.strip()),
        "file_hashes": file_hashes(workspace),
        "git_diff": diff,
        "evidence_files": evidence_file_snapshots(workspace, evidence_paths or []),
    }


def read_event_log(path: Path, label: str) -> dict[str, Any]:
    try:
        raw = path.read_bytes()
    except OSError as exc:
        raise EvalError(f"{label} 无法读取: {exc}") from exc
    events: list[dict[str, Any]] = []
    for line_no, line in enumerate(raw.decode("utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise EvalError(f"{label} 第 {line_no} 行不是合法 JSON: {exc}") from exc
        if not isinstance(value, dict) or not isinstance(value.get("kind"), str) or not value["kind"].strip():
            raise EvalError(f"{label} 第 {line_no} 行必须包含非空 kind")
        events.append(value)
    if not events:
        raise EvalError(f"{label} 不能为空")
    return {
        "sha256": sha256_bytes(raw),
        "count": len(events),
        "kinds": sorted({event["kind"] for event in events}),
        "events": events,
    }


def prepare_harness(case: dict[str, Any], repo_root: Path, evaluation_id: str) -> dict[str, Any] | None:
    config = case.get("harness")
    if config is None:
        return None
    if not isinstance(config, dict):
        raise EvalError(f"{case['id']}: harness 必须是对象")
    fixture = safe_repo_path(repo_root, config.get("fixture"), f"{case['id']}: harness.fixture")
    if not fixture.is_dir():
        raise EvalError(f"{case['id']}: harness.fixture 必须是目录")
    expected = config.get("expected_changed_paths")
    protected = config.get("protected_paths")
    unchanged = config.get("expected_unchanged_paths", [])
    required_event_kinds = config.get("required_event_kinds")
    evidence = config.get("evidence_paths", [])
    if not isinstance(expected, list) or any(not isinstance(item, str) for item in expected):
        raise EvalError(f"{case['id']}: harness.expected_changed_paths 必须是字符串数组")
    if not isinstance(protected, list) or any(not isinstance(item, str) for item in protected):
        raise EvalError(f"{case['id']}: harness.protected_paths 必须是字符串数组")
    if not isinstance(unchanged, list) or any(not isinstance(item, str) for item in unchanged):
        raise EvalError(f"{case['id']}: harness.expected_unchanged_paths 必须是字符串数组")
    if not isinstance(required_event_kinds, list) or any(
        not isinstance(item, str) or not item.strip() for item in required_event_kinds
    ):
        raise EvalError(f"{case['id']}: harness.required_event_kinds 必须是字符串数组")
    if not isinstance(evidence, list) or any(not isinstance(item, str) for item in evidence):
        raise EvalError(f"{case['id']}: harness.evidence_paths 必须是字符串数组")
    expected_paths = [fixture_relative_path(item, f"{case['id']}: expected_changed_paths") for item in expected]
    protected_paths = [fixture_relative_path(item, f"{case['id']}: protected_paths") for item in protected]
    unchanged_paths = [fixture_relative_path(item, f"{case['id']}: expected_unchanged_paths") for item in unchanged]
    evidence_paths = [fixture_relative_path(item, f"{case['id']}: evidence_paths") for item in evidence]

    temp_root = Path(tempfile.mkdtemp(prefix=f"pmai-session-eval-{evaluation_id[:8]}-"))
    workspace = temp_root / "workspace"
    event_log = temp_root / "events.jsonl"
    try:
        shutil.copytree(fixture, workspace)
        for path in unchanged_paths:
            if not (workspace / path).is_file():
                raise EvalError(f"{case['id']}: expected_unchanged_paths 不存在: {path}")
        for path in evidence_paths:
            if not (workspace / path).is_file() and not (workspace / path).is_symlink():
                raise EvalError(f"{case['id']}: evidence_paths 不存在: {path}")
        run_git(workspace, ["init", "-q"], "fixture git init")
        run_git(workspace, ["config", "user.email", "pmai-session-eval@example.invalid"], "fixture git config")
        run_git(workspace, ["config", "user.name", "PMAI Session Eval"], "fixture git config")
        run_git(workspace, ["add", "--all"], "fixture git add")
        run_git(workspace, ["commit", "-q", "-m", "fixture baseline"], "fixture git commit")
        state_home, allow_initial_dirty = apply_fixture_setup(
            workspace,
            config.get("setup", {}),
            repo_root,
            temp_root,
        )
        event_log.write_text("", encoding="utf-8")
        baseline = snapshot_workspace(workspace, evidence_paths=evidence_paths)
        if not baseline["clean"] and not allow_initial_dirty:
            raise EvalError(f"{case['id']}: fixture baseline 不干净")
        return {
            "temp_root": temp_root,
            "workspace": workspace,
            "baseline": baseline,
            "expected_paths": expected_paths,
            "protected_paths": protected_paths,
            "unchanged_paths": unchanged_paths,
            "required_event_kinds": required_event_kinds,
            "evidence_paths": evidence_paths,
            "event_log": event_log,
            "state_home": state_home,
            "allow_initial_dirty": allow_initial_dirty,
        }
    except Exception:
        shutil.rmtree(temp_root, ignore_errors=True)
        raise


def build_evidence_manifest(
    case: dict[str, Any],
    case_payload: dict[str, Any],
    result: dict[str, Any],
    context: dict[str, Any],
    evaluation_id: str,
) -> dict[str, Any]:
    baseline = context["baseline"]
    after = snapshot_workspace(
        context["workspace"], baseline["commit"], context.get("evidence_paths", [])
    )
    event_log = read_event_log(context["event_log"], f"{case['id']}: event log")
    baseline_files = baseline["file_hashes"]
    after_files = after["file_hashes"]
    changed_paths = sorted(
        path
        for path in set(baseline_files) | set(after_files)
        if baseline_files.get(path) != after_files.get(path)
    )
    protected = [
        path
        for path in changed_paths
        if any(path == protected_path or path.startswith(f"{protected_path}/") for protected_path in context["protected_paths"])
    ]
    missing_expected = sorted(set(context["expected_paths"]) - set(changed_paths))
    unchanged_violations = sorted(set(context["unchanged_paths"]) & set(changed_paths))
    independent = {
        "baseline_commit": baseline["commit"],
        "baseline_clean": baseline["clean"],
        "baseline_status": baseline["status"],
        "allow_initial_dirty": context["allow_initial_dirty"],
        "baseline_file_hashes": baseline_files,
        "evidence_files": {
            "paths": context.get("evidence_paths", []),
            "baseline": baseline.get("evidence_files", {}),
            "final": after.get("evidence_files", {}),
        },
        "final_commit": after["commit"],
        "final_clean": after["clean"],
        "final_file_hashes": after_files,
        "changed_paths": changed_paths,
        "expected_changed_paths": context["expected_paths"],
        "missing_expected_paths": missing_expected,
        "expected_unchanged_paths": context["unchanged_paths"],
        "unchanged_violations": unchanged_violations,
        "protected_paths": context["protected_paths"],
        "protected_violations": protected,
        "git_diff": after["git_diff"],
        "event_log": event_log,
        "framework_revision": run_git(Path(__file__).resolve().parent.parent, ["rev-parse", "HEAD"], "framework revision").strip(),
        "framework_clean": not bool(run_git(
            Path(__file__).resolve().parent.parent,
            ["status", "--porcelain=v1", "--untracked-files=all"],
            "framework status",
        ).strip()),
    }
    if isinstance(result.get("runtime"), dict):
        independent["runtime"] = result["runtime"]
    core = {
        "schema_version": SCHEMA_VERSION,
        "evaluation_id": evaluation_id,
        "case_id": case["id"],
        "case_sha256": sha256_json(case_payload),
        "runner_result_sha256": sha256_json(result),
        "independent_evidence": independent,
    }
    return {**core, "digest": sha256_json(core)}


def validate_evidence_manifest(
    case: dict[str, Any],
    case_payload: dict[str, Any],
    result: dict[str, Any],
    manifest: dict[str, Any] | None,
    evaluation_id: str,
    require_runtime: bool = False,
) -> list[str]:
    if "harness" not in case:
        return []
    if not isinstance(manifest, dict):
        return ["独立证据 manifest 缺失"]
    problems: list[str] = []
    missing = sorted(REQUIRED_MANIFEST_FIELDS - set(manifest))
    if missing:
        return [f"独立证据 manifest 缺字段: {missing}"]
    if manifest.get("schema_version") != SCHEMA_VERSION:
        problems.append("独立证据 manifest schema_version 不匹配")
    if manifest.get("evaluation_id") != evaluation_id:
        problems.append("独立证据 evaluation_id 不匹配")
    if manifest.get("case_id") != case["id"]:
        problems.append("独立证据 case_id 不匹配")
    if manifest.get("case_sha256") != sha256_json(case_payload):
        problems.append("独立证据 case digest 不匹配")
    if manifest.get("runner_result_sha256") != sha256_json(result):
        problems.append("独立证据 runner digest 不匹配")
    evidence = manifest.get("independent_evidence")
    if not isinstance(evidence, dict):
        problems.append("独立证据 independent_evidence 必须是对象")
    else:
        if evidence.get("baseline_clean") is not True and evidence.get("allow_initial_dirty") is not True:
            problems.append("独立证据 baseline 必须干净")
        if evidence.get("missing_expected_paths"):
            problems.append(f"独立证据未观察到预期修改: {evidence['missing_expected_paths']}")
        if evidence.get("unchanged_violations"):
            problems.append(f"独立证据发现预期不变文件被修改: {evidence['unchanged_violations']}")
        if evidence.get("protected_violations"):
            problems.append(f"独立证据发现越界修改: {evidence['protected_violations']}")
        configured_evidence = case.get("harness", {}).get("evidence_paths", [])
        evidence_files = evidence.get("evidence_files")
        if configured_evidence:
            if not isinstance(evidence_files, dict):
                problems.append("独立证据 evidence_files 缺失")
            elif evidence_files.get("paths") != configured_evidence:
                problems.append("独立证据 evidence_files 路径与案例配置不一致")
            else:
                for phase in ("baseline", "final"):
                    values = evidence_files.get(phase)
                    if not isinstance(values, dict) or any(
                        path not in values for path in configured_evidence
                    ):
                        problems.append(f"独立证据 evidence_files.{phase} 缺少配置路径")
        event_log = evidence.get("event_log")
        required_kinds = case.get("harness", {}).get("required_event_kinds", [])
        if not isinstance(event_log, dict) or not isinstance(event_log.get("events"), list):
            problems.append("独立证据 event_log 缺失或格式不合法")
        else:
            observed_kinds = set(event_log.get("kinds", []))
            missing_kinds = sorted(set(required_kinds) - observed_kinds)
            if missing_kinds:
                problems.append(f"独立证据缺少事件类型: {missing_kinds}")
            if event_log.get("count") != len(event_log["events"]):
                problems.append("独立证据 event_log count 不匹配")
        if require_runtime:
            provenance = result.get("provenance")
            if evidence.get("framework_revision") != (provenance or {}).get("framework_revision"):
                problems.append("独立证据 framework_revision 与 runner 不匹配")
            if evidence.get("runtime") != result.get("runtime"):
                problems.append("独立证据 runtime 与 runner 不匹配")
    digest = manifest.get("digest")
    if not isinstance(digest, str) or digest != sha256_json({key: value for key, value in manifest.items() if key != "digest"}):
        problems.append("独立证据总 digest 无法复算")
    return problems


def validate_provenance(value: Any, label: str) -> list[str]:
    if not isinstance(value, dict):
        return [f"{label} 必须是对象"]
    problems = []
    for field in sorted(REQUIRED_PROVENANCE_FIELDS):
        if not isinstance(value.get(field), str) or not value[field].strip():
            problems.append(f"{label}.{field} 必须是非空字符串")
    return problems


def validate_runtime_evidence(
    result: dict[str, Any], label: str, *, required: bool
) -> list[str]:
    if not required:
        return []
    runtime = result.get("runtime")
    if not isinstance(runtime, dict):
        return [f"{label}.runtime 必须是对象"]
    problems: list[str] = []
    missing = sorted(REQUIRED_RUNTIME_FIELDS - set(runtime))
    if missing:
        return [f"{label}.runtime 缺字段: {missing}"]
    for field in ("started_at", "ended_at"):
        if not isinstance(runtime.get(field), str) or not runtime[field].strip():
            problems.append(f"{label}.runtime.{field} 必须是非空字符串")
    if not isinstance(runtime.get("duration_ms"), (int, float)) or runtime["duration_ms"] < 0:
        problems.append(f"{label}.runtime.duration_ms 必须是非负数")

    token_usage = runtime.get("token_usage")
    if not isinstance(token_usage, dict):
        problems.append(f"{label}.runtime.token_usage 必须是对象")
    else:
        token_status = token_usage.get("status")
        if token_status not in VALID_RUNTIME_STATUSES:
            problems.append(f"{label}.runtime.token_usage.status 不支持: {token_status}")
        if token_status == "reported":
            for field in ("input_tokens", "output_tokens", "total_tokens"):
                if not isinstance(token_usage.get(field), int) or token_usage[field] < 0:
                    problems.append(f"{label}.runtime.token_usage.{field} 必须是非负整数")
        elif not isinstance(token_usage.get("reason"), str) or not token_usage["reason"].strip():
            problems.append(f"{label}.runtime.token_usage.reason 必须说明为何不可用")

    cost = runtime.get("cost")
    if not isinstance(cost, dict):
        problems.append(f"{label}.runtime.cost 必须是对象")
    else:
        cost_status = cost.get("status")
        if cost_status not in VALID_RUNTIME_STATUSES:
            problems.append(f"{label}.runtime.cost.status 不支持: {cost_status}")
        if cost_status == "reported":
            if cost.get("currency") != "USD":
                problems.append(f"{label}.runtime.cost.currency 必须为 USD")
            if not isinstance(cost.get("amount_usd"), (int, float)) or cost["amount_usd"] < 0:
                problems.append(f"{label}.runtime.cost.amount_usd 必须是非负数")
        elif not isinstance(cost.get("reason"), str) or not cost["reason"].strip():
            problems.append(f"{label}.runtime.cost.reason 必须说明为何不可用")

    failure = runtime.get("failure")
    if not isinstance(failure, dict) or failure.get("status") not in VALID_FAILURE_STATUSES:
        problems.append(f"{label}.runtime.failure.status 必须为 none 或 error")
    elif failure["status"] == "error" and (
        not isinstance(failure.get("reason"), str) or not failure["reason"].strip()
    ):
        problems.append(f"{label}.runtime.failure.reason 必须说明失败原因")

    provenance = result.get("provenance")
    if isinstance(provenance, dict):
        for field in ("framework_revision", "consumer_revision"):
            if not isinstance(provenance.get(field), str) or not provenance[field].strip():
                problems.append(f"{label}.provenance.{field} 必须是非空字符串")
        if provenance.get("host") in {"fixture", "fake", "test"}:
            problems.append(f"{label}.provenance.host 不能是 fixture/test runner")
    return problems


def validate_runner_result(
    case: dict[str, Any], result: dict[str, Any], evaluation_id: str, *, require_runtime: bool = False
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
    problems.extend(validate_runtime_evidence(result, "runner", required=require_runtime))
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

    # Runner claims are deliberately untrusted. Expected outcomes are private to
    # the evaluator and are checked against independent workspace evidence and a
    # separate semantic Judge, never against the model's own declared fields.
    if result.get("claims_trust") not in {None, "unverified"}:
        problems.append("runner claims_trust 必须标记为 unverified")
    return problems


def validate_judge_result(
    case: dict[str, Any],
    result: dict[str, Any],
    judge: dict[str, Any],
    evaluation_id: str,
    evidence_manifest: dict[str, Any] | None = None,
    require_runtime: bool = False,
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
        required_evidence = set(REQUIRED_JUDGE_EVIDENCE)
        if evidence_manifest is not None:
            required_evidence.update({"independent_evidence", "manifest", "digest", "event_log"})
        if require_runtime:
            required_evidence.update({"runtime", "framework_revision", "consumer_revision"})
        missing = sorted(required_evidence - set(reviewed))
        if missing:
            problems.append(f"judge 未声明检查完整 runner 证据: {missing}")

    if evidence_manifest is not None:
        if judge.get("evidence_digest") != evidence_manifest.get("digest"):
            problems.append("judge evidence_digest 与当前证据 manifest 不匹配")

    runner_provenance = result.get("provenance")
    judge_provenance = judge.get("provenance")
    if isinstance(runner_provenance, dict) and isinstance(judge_provenance, dict):
        if runner_provenance.get("run_id") == judge_provenance.get("run_id"):
            problems.append("judge 必须使用独立于 runner 的 run_id")
    if judge.get("pass") is False:
        problems.append(f"judge 未通过: {judge.get('reason', 'no reason')}")
    return problems


def validate_semantic_judge_result(
    case: dict[str, Any],
    result: dict[str, Any],
    judge: dict[str, Any],
    evaluation_id: str,
    evidence_manifest: dict[str, Any] | None = None,
) -> list[str]:
    """Validate a semantic Judge without trusting its pass flag blindly."""
    problems: list[str] = []
    if judge.get("assessment_type") != "semantic-llm-v1":
        problems.append("semantic judge assessment_type 必须为 semantic-llm-v1")
    if judge.get("case_id") != case["id"]:
        problems.append("semantic judge case_id 与当前案例不一致")
    if judge.get("evaluation_id") != evaluation_id:
        problems.append("semantic judge evaluation_id 与当前执行不一致")
    if not isinstance(judge.get("pass"), bool):
        problems.append("semantic judge pass 必须是布尔值")
    elif judge["pass"] is False:
        problems.append(f"semantic judge 未通过: {judge.get('reason', 'no reason')}")
    if not isinstance(judge.get("reason"), str) or not judge["reason"].strip():
        problems.append("semantic judge reason 必须是非空字符串")
    problems.extend(validate_provenance(judge.get("provenance"), "semantic judge provenance"))

    rubric = case.get("judge", {}).get("rubric", [])
    scores = judge.get("criterion_scores")
    if not isinstance(scores, list):
        problems.append("semantic judge criterion_scores 必须是数组")
    else:
        seen: set[str] = set()
        all_max = True
        for index, item in enumerate(scores, 1):
            if not isinstance(item, dict):
                problems.append(f"semantic judge criterion_scores[{index}] 必须是对象")
                continue
            criterion = item.get("criterion")
            score = item.get("score")
            explanation = item.get("reason")
            if not isinstance(criterion, str) or not criterion.strip():
                problems.append(f"semantic judge criterion_scores[{index}].criterion 非法")
                continue
            if criterion in seen:
                problems.append(f"semantic judge criterion 重复: {criterion}")
            seen.add(criterion)
            if not isinstance(score, int) or score not in {0, 1, 2}:
                problems.append(f"semantic judge criterion_scores[{index}].score 必须为 0/1/2")
            elif score != 2:
                all_max = False
            if not isinstance(explanation, str) or not explanation.strip():
                problems.append(f"semantic judge criterion_scores[{index}].reason 必须是非空字符串")
        ordered = [item.get("criterion") for item in scores if isinstance(item, dict)]
        if ordered != rubric:
            problems.append("semantic judge criterion_scores 必须按隐藏 rubric 原文、原顺序逐条覆盖且不能多报")
        if isinstance(judge.get("pass"), bool) and judge["pass"] != all_max:
            problems.append("semantic judge pass 必须与全部 criterion score=2 的结果一致")

    for field in ("findings", "root_causes"):
        value = judge.get(field)
        if not isinstance(value, list) or any(not isinstance(item, str) or not item.strip() for item in value):
            problems.append(f"semantic judge {field} 必须是非空字符串数组或空数组")

    reviewed = judge.get("reviewed_evidence")
    if not isinstance(reviewed, list) or any(not isinstance(item, str) for item in reviewed):
        problems.append("semantic judge reviewed_evidence 必须是字符串数组")
    elif not REQUIRED_SEMANTIC_EVIDENCE.issubset(set(reviewed)):
        problems.append(
            f"semantic judge 未声明检查完整证据: {sorted(REQUIRED_SEMANTIC_EVIDENCE - set(reviewed))}"
        )
    if evidence_manifest is not None and judge.get("evidence_digest") != evidence_manifest.get("digest"):
        problems.append("semantic judge evidence_digest 与当前证据 manifest 不匹配")
    runner_provenance = result.get("provenance")
    judge_provenance = judge.get("provenance")
    if isinstance(runner_provenance, dict) and isinstance(judge_provenance, dict):
        if runner_provenance.get("run_id") == judge_provenance.get("run_id"):
            problems.append("semantic judge 必须使用独立于 runner 的 run_id")
    return problems


def persist_result(
    results_dir: Path,
    case: dict[str, Any],
    result: dict[str, Any],
    judge: Any,
    evidence_manifest: dict[str, Any] | None = None,
    semantic_judge: Any = None,
) -> None:
    results_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": SCHEMA_VERSION,
        "case_id": case["id"],
        "saved_at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "runner_result": result,
        "judge_result": judge,
    }
    if evidence_manifest is not None:
        payload["evidence_manifest"] = evidence_manifest
    if semantic_judge is not None:
        payload["semantic_judge_result"] = semantic_judge
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
    parser.add_argument(
        "--session-case",
        action="append",
        dest="session_case_ids",
        default=[],
        help="只执行指定的 session case；static case 仍按 --mode 选择",
    )
    parser.add_argument("--runner-command", default=os.environ.get("PMAI_SKILL_EVAL_RUNNER", ""))
    parser.add_argument("--judge-command", default=os.environ.get("PMAI_SKILL_EVAL_JUDGE", ""))
    parser.add_argument(
        "--semantic-judge-command",
        default=os.environ.get("PMAI_SKILL_EVAL_SEMANTIC_JUDGE", ""),
        help="只读语义能力 Judge 命令；它接收完整案例但不接触 Runner 进程",
    )
    parser.add_argument("--require-runner", action="store_true")
    parser.add_argument("--require-judge", action="store_true")
    parser.add_argument(
        "--require-semantic-judge",
        action="store_true",
        help="session case 必须有独立语义 Judge 才能通过",
    )
    parser.add_argument(
        "--require-runtime-evidence",
        action="store_true",
        help="session runner 必须提供 revision、耗时、Token、费用和失败记录",
    )
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

    if args.session_case_ids:
        requested_session = set(args.session_case_ids)
        known = {case["id"] for case in cases}
        unknown = sorted(requested_session - known)
        if unknown:
            print(f"FAIL unknown session cases: {unknown}")
            return 1
        non_session = sorted(
            case["id"]
            for case in cases
            if case["id"] in requested_session and case["layer"] != "session"
        )
        if non_session:
            print(f"FAIL --session-case 只能指定 session case: {non_session}")
            return 1

    print(f"PASS schema: {len(cases)} cases + touchfiles")
    if args.mode == "validate":
        return 0

    selected_layers = VALID_LAYERS if args.mode == "all" else {args.mode}
    require_runtime = args.require_runtime_evidence or os.environ.get("PMAI_REQUIRE_RUNTIME_EVIDENCE") == "1"
    require_semantic_judge = args.require_semantic_judge or os.environ.get("PMAI_REQUIRE_SEMANTIC_JUDGE") == "1"
    requested_session = set(args.session_case_ids)
    selected = [
        case
        for case in cases
        if case["layer"] in selected_layers
        and (
            case["layer"] != "session"
            or not requested_session
            or case["id"] in requested_session
        )
    ]
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
        harness_context: dict[str, Any] | None = None
        evidence_manifest: dict[str, Any] | None = None
        judge_result: dict[str, Any] | None = None
        semantic_judge_result: dict[str, Any] | None = None
        try:
            try:
                harness_context = prepare_harness(case, repo_root, evaluation_id)
                runner_case_payload = build_runner_case_payload(case_payload, harness_context)
                runner_payload = {
                    "schema_version": SCHEMA_VERSION,
                    "evaluation_id": evaluation_id,
                    "case": runner_case_payload,
                }
                result = run_external(args.runner_command, runner_payload, args.timeout, f"runner {case_id}")
                problems = validate_runner_result(
                    case, result, evaluation_id, require_runtime=require_runtime
                )
            except EvalError as exc:
                problems = [str(exc)]
                result = {}

            if not problems and harness_context is not None:
                try:
                    evidence_manifest = build_evidence_manifest(
                        case, case_payload, result, harness_context, evaluation_id
                    )
                    problems.extend(
                        validate_evidence_manifest(
                            case,
                            case_payload,
                            result,
                            evidence_manifest,
                            evaluation_id,
                            require_runtime=require_runtime,
                        )
                    )
                except EvalError as exc:
                    problems.append(str(exc))

            if not problems and case.get("judge", {}).get("enabled"):
                if args.judge_command:
                    try:
                        judge_payload = {
                            "schema_version": SCHEMA_VERSION,
                            "evaluation_id": evaluation_id,
                            "case": case_payload,
                            "result": result,
                        }
                        if evidence_manifest is not None:
                            judge_payload["evidence_manifest"] = evidence_manifest
                        judge_result = run_external(
                            args.judge_command,
                            judge_payload,
                            args.timeout,
                            f"judge {case_id}",
                        )
                        problems.extend(
                            validate_judge_result(
                                case,
                                result,
                                judge_result,
                                evaluation_id,
                                evidence_manifest,
                                require_runtime=require_runtime,
                            )
                        )
                    except EvalError as exc:
                        problems.append(str(exc))
                elif args.require_judge:
                    problems.append("LLM judge 未配置")
                else:
                    judge_skipped += 1
                    print(f"SKIP judge {case_id}: LLM judge 未配置")
                    if result:
                        persist_result(results_dir, case, result, None, evidence_manifest)
                    skipped += 1
                    continue

            if not problems and require_semantic_judge and not args.judge_command:
                problems.append("semantic Judge 依赖确定性证据 Judge，当前未配置 --judge-command")

            if not problems and (args.semantic_judge_command or require_semantic_judge):
                if args.semantic_judge_command:
                    try:
                        semantic_payload = {
                            "schema_version": SCHEMA_VERSION,
                            "evaluation_id": evaluation_id,
                            "case": case_payload,
                            "result": result,
                        }
                        if evidence_manifest is not None:
                            semantic_payload["evidence_manifest"] = evidence_manifest
                        semantic_judge_result = run_external(
                            args.semantic_judge_command,
                            semantic_payload,
                            args.timeout,
                            f"semantic judge {case_id}",
                        )
                        problems.extend(
                            validate_semantic_judge_result(
                                case,
                                result,
                                semantic_judge_result,
                                evaluation_id,
                                evidence_manifest,
                            )
                        )
                    except EvalError as exc:
                        problems.append(str(exc))
                else:
                    problems.append("semantic Judge 未配置")

            if result:
                persist_result(
                    results_dir,
                    case,
                    result,
                    judge_result,
                    evidence_manifest,
                    semantic_judge_result,
                )
        finally:
            if harness_context is not None:
                shutil.rmtree(harness_context["temp_root"], ignore_errors=True)
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
