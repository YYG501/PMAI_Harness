#!/usr/bin/env python3
"""Run declared final checks in a detached validation worktree.

The active development worktree and its dev server are never stopped or reused.
Results are written back to the caller-selected audit artifact.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from _lib.project_definition import ProjectDefinitionError, load_project_definition


VALID_CHECKS = ("test", "typecheck", "build")


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def read_build(module_dir: Path) -> dict:
    meta_path = module_dir / ".work-meta.json"
    if not meta_path.is_file():
        raise SystemExit(f"缺少 build 合同：{meta_path}")
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f".work-meta.json 不是合法 JSON：{exc}") from exc
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit("缺少 build 合同。")
    commit = str(build.get("implementation_commit") or "").strip()
    finalization = build.get("finalization")
    if not commit:
        raise SystemExit("build 合同缺少 implementation_commit。")
    if not isinstance(finalization, dict) or not finalization.get("requested_at"):
        raise SystemExit("PM 尚未请求定稿，不能运行隔离的完整验证。")
    if str(finalization.get("requested_commit") or "") != commit:
        raise SystemExit("定稿请求与 implementation_commit 不一致。")
    return build


def git(repo_root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", *args],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def run_command(command: str, cwd: Path, log_path: Path) -> dict:
    started_at = now_iso()
    started = datetime.now(timezone.utc)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["PMAI_VALIDATION"] = "1"
    with log_path.open("w", encoding="utf-8") as log:
        result = subprocess.run(
            command,
            cwd=cwd,
            shell=True,
            executable="/bin/bash",
            stdout=log,
            stderr=subprocess.STDOUT,
            env=env,
            check=False,
        )
    duration = (datetime.now(timezone.utc) - started).total_seconds()
    return {
        "command": command,
        "status": "pass" if result.returncode == 0 else "fail",
        "exit_code": result.returncode,
        "started_at": started_at,
        "ended_at": now_iso(),
        "duration_seconds": round(duration, 3),
        "log": str(log_path),
    }


def start_timing(audit_path: Path, phase: str) -> str:
    result = subprocess.run(
        [
            sys.executable,
            str(Path(__file__).with_name("build-timing.py")),
            "start",
            "--audit-file",
            str(audit_path.parent / "timing.json"),
            "--phase",
            phase,
            "--kind",
            "final",
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or f"无法开始 {phase} timing。")
    return str(json.loads(result.stdout)["id"])


def finish_timing(audit_path: Path, entry_id: str, status: str, reason: str | None) -> str | None:
    command = [
        sys.executable,
        str(Path(__file__).with_name("build-timing.py")),
        "finish",
        "--audit-file",
        str(audit_path.parent / "timing.json"),
        "--id",
        entry_id,
        "--status",
        status,
    ]
    if reason:
        command.extend(["--reason", reason])
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    return result.stderr.strip() or "timing finish failed" if result.returncode != 0 else None


def run_validation(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).expanduser().resolve()
    module_dir = Path(args.module_dir).expanduser()
    module_dir = module_dir.resolve() if module_dir.is_absolute() else (repo_root / module_dir).resolve()
    audit_path = Path(args.audit).expanduser()
    audit_path = audit_path if audit_path.is_absolute() else repo_root / audit_path
    build = read_build(module_dir)
    commit = str(build["implementation_commit"])
    if git(repo_root, "cat-file", "-e", f"{commit}^{{commit}}").returncode != 0:
        raise SystemExit(f"implementation_commit 不存在：{commit}")

    worktree = Path(tempfile.mkdtemp(prefix="pmai-final-validation-"))
    worktree.rmdir()
    artifact = {
        "schema_version": 1,
        "check": "final-validation",
        "status": "running",
        "implementation_commit": commit,
        "source_hash": build.get("approved_source_hash"),
        "requested_at": build["finalization"]["requested_at"],
        "started_at": now_iso(),
        "ended_at": None,
        "validation_worktree": str(worktree),
        "active_worktree_untouched": True,
        "commands": [],
        "cleanup": {"status": "pending", "path": str(worktree)},
    }
    write_json(audit_path, artifact)
    timing_id = start_timing(audit_path, "final-validation")
    artifact["timing_entry_id"] = timing_id
    added = False
    checks_passed = False
    try:
        added_result = git(repo_root, "worktree", "add", "--detach", str(worktree), commit)
        if added_result.returncode != 0:
            artifact["status"] = "fail"
            artifact["error"] = added_result.stderr.strip() or "git worktree add failed"
            return 1
        added = True
        try:
            definition = load_project_definition(worktree / ".pm-workflow" / "project.yml")
        except ProjectDefinitionError as exc:
            artifact["status"] = "fail"
            artifact["error"] = str(exc)
            return 1
        implementation_root = str(definition["implementation"]["root"])
        execution_root = (worktree / implementation_root).resolve()
        try:
            execution_root.relative_to(worktree.resolve())
        except ValueError:
            artifact["status"] = "fail"
            artifact["error"] = (
                "project.yml implementation.root 通过 symlink 逃逸 validation worktree："
                f"{implementation_root}"
            )
            return 1
        if not execution_root.is_dir():
            artifact["status"] = "fail"
            artifact["error"] = (
                "project.yml implementation.root 不存在或不是目录："
                f"{implementation_root}"
            )
            return 1
        artifact["implementation_root"] = implementation_root
        artifact["execution_root"] = str(execution_root)
        configured = definition["commands"]
        selected = list(dict.fromkeys(args.check or VALID_CHECKS))
        commands: list[dict[str, object]] = []
        if configured.get("install"):
            commands.append(
                {
                    "name": "install",
                    "command": str(configured["install"]),
                    "satisfies": ["install"],
                }
            )
        for name in selected:
            command = configured.get(name)
            if command:
                command_text = str(command)
                duplicate = next(
                    (
                        item
                        for item in commands
                        if item["name"] != "install" and item["command"] == command_text
                    ),
                    None,
                )
                if duplicate is not None:
                    duplicate["satisfies"].append(name)  # type: ignore[union-attr]
                else:
                    commands.append(
                        {"name": name, "command": command_text, "satisfies": [name]}
                    )
        if not commands:
            artifact["status"] = "fail"
            artifact["error"] = "project.yml 没有可运行的 final validation 命令。"
            return 1

        log_dir = audit_path.parent / "final-validation-logs"
        artifact["requested_checks"] = selected
        for item in commands:
            name = str(item["name"])
            command = str(item["command"])
            result = run_command(command, execution_root, log_dir / f"{name}.log")
            result["name"] = name
            result["satisfies"] = item["satisfies"]
            artifact["commands"].append(result)
            write_json(audit_path, artifact)
            if result["status"] != "pass":
                artifact["status"] = "fail"
                return 1
        artifact["status"] = "pass"
        checks_passed = True
        return 0
    finally:
        cleanup_error = None
        if added:
            cleanup = git(repo_root, "worktree", "remove", "--force", str(worktree))
            if cleanup.returncode != 0:
                cleanup_error = cleanup.stderr.strip() or "git worktree remove failed"
        elif worktree.exists():
            try:
                worktree.rmdir()
            except OSError as exc:
                cleanup_error = str(exc)
        if cleanup_error:
            artifact["cleanup"] = {
                "status": "pending",
                "path": str(worktree),
                "error": cleanup_error,
            }
        else:
            artifact["cleanup"] = {"status": "complete", "path": str(worktree)}
        artifact["ended_at"] = now_iso()
        if artifact["status"] == "running":
            artifact["status"] = "pass" if checks_passed else "fail"
        failed_command = next(
            (item for item in artifact["commands"] if item.get("status") == "fail"),
            None,
        )
        reason = str(artifact.get("error") or "") or (
            f"{failed_command.get('name')} failed" if failed_command else None
        )
        timing_error = finish_timing(audit_path, timing_id, artifact["status"], reason)
        if timing_error:
            artifact["timing_error"] = timing_error
        write_json(audit_path, artifact)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo-root", default=".")
    result.add_argument("--module-dir", required=True)
    result.add_argument("--audit", required=True)
    result.add_argument("--check", action="append", choices=VALID_CHECKS, default=[])
    return result


def main(argv: list[str] | None = None) -> int:
    return run_validation(parser().parse_args(argv))


if __name__ == "__main__":
    raise SystemExit(main())
