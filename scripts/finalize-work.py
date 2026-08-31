#!/usr/bin/env python3
"""Resume and run the mechanical PMAI finalization steps from contract state."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from _lib.work_contract import WorkContractError, normalize_work_contract
from _lib.final_validation import LIMITABLE_CHECKS, command_statuses, exception_allows
from _lib.agent_roles import build_receipt, new_run_id, validate_backend


COMMAND_CHECKS = {"tests": "test", "typecheck": "typecheck", "build": "build"}
LEGACY_BROWSER_CHECKS = {"browser-smoke", "visual", "behavior"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"文件不存在：{path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"JSON 不合法：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"JSON 顶层必须是对象：{path}")
    return value


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def run(
    command: list[str],
    *,
    cwd: Path,
    capture: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        env=env,
        check=False,
    )


def require_ok(result: subprocess.CompletedProcess[str], label: str) -> None:
    if result.returncode != 0:
        detail = (result.stderr or "").strip()
        raise SystemExit(f"{label} 失败" + (f"：{detail}" if detail else "。"))


def git_root(path: Path) -> Path:
    result = run(["git", "-C", str(path), "rev-parse", "--show-toplevel"], cwd=path, capture=True)
    require_ok(result, "定位 build worktree")
    return Path(result.stdout.strip()).resolve()


def git_revision(path: Path) -> str:
    result = run(["git", "-C", str(path), "rev-parse", "HEAD"], cwd=path, capture=True)
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return "unknown"


def git_clean(path: Path) -> bool | None:
    result = run(
        ["git", "-C", str(path), "status", "--porcelain=v1", "--untracked-files=all"],
        cwd=path,
        capture=True,
    )
    if result.returncode != 0:
        return None
    return not bool(result.stdout.strip())


def main_repo_root(build_root: Path) -> Path:
    result = run(
        ["git", "-C", str(build_root), "rev-parse", "--git-common-dir"],
        cwd=build_root,
        capture=True,
    )
    require_ok(result, "定位主仓")
    common = Path(result.stdout.strip())
    common = common if common.is_absolute() else (build_root / common).resolve()
    return common.parent.resolve()


def timing(script_dir: Path, audit_dir: Path, action: str, *args: str) -> str:
    result = run(
        [
            sys.executable,
            str(script_dir / "build-timing.py"),
            action,
            "--audit-file",
            str(audit_dir / "timing.json"),
            *args,
        ],
        cwd=audit_dir.parent,
        capture=True,
    )
    require_ok(result, f"timing {action}")
    return result.stdout.strip()


def currentness_check(script_dir: Path, build_root: Path, module_dir: Path, audit_dir: Path) -> None:
    started = json.loads(
        timing(script_dir, audit_dir, "start", "--phase", "currentness", "--kind", "final")
    )
    result = run(
        [
            sys.executable,
            str(script_dir / "build-contract.py"),
            "validate-final-currentness",
            str(module_dir),
        ],
        cwd=build_root,
        capture=True,
    )
    status = "pass" if result.returncode == 0 else "fail"
    finish_args = ["--id", started["id"], "--status", status]
    if result.returncode != 0:
        finish_args.extend(["--reason", (result.stderr or "currentness failed").strip()])
    timing(script_dir, audit_dir, "finish", *finish_args)
    require_ok(result, "定稿 currentness")


def build_state(module_dir: Path) -> tuple[dict, dict]:
    meta = read_json(module_dir / ".work-meta.json")
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit(".work-meta.json 缺少 build 合同。")
    try:
        contract = normalize_work_contract(meta)
    except WorkContractError as exc:
        raise SystemExit(str(exc)) from exc
    if (contract.contract_version or 0) < 4:
        raise SystemExit("统一 finalize runner 只处理 v4+；v2/v3 继续走 /pmai-build-close 恢复。")
    return meta, build


def audit_dir_for(build_root: Path, module_dir: Path, build: dict) -> Path:
    raw = str(build.get("audit_dir") or "").strip()
    if not raw:
        return build_root / ".pm-workflow" / "audits" / module_dir.name
    path = Path(raw)
    resolved = (path if path.is_absolute() else build_root / path).resolve()
    try:
        resolved.relative_to(build_root.resolve())
    except ValueError as exc:
        raise SystemExit("build.audit_dir 必须位于当前仓库内。") from exc
    return resolved


def evidence_names(build: dict) -> set[str]:
    acceptance = build.get("acceptance")
    if not isinstance(acceptance, dict):
        return set()
    evidence = acceptance.get("evidence")
    if not isinstance(evidence, list):
        return set()
    return {
        str(item.get("name"))
        for item in evidence
        if isinstance(item, dict) and item.get("name")
    }


def final_checks(build: dict) -> list[str]:
    try:
        return list(normalize_work_contract({"build": build}).final_checks)
    except WorkContractError as exc:
        raise SystemExit(str(exc)) from exc


def finalization_marker_path(audit_dir: Path) -> Path:
    return audit_dir / "finalize-run.json"


def marker_is_current(path: Path, build: dict) -> bool:
    if not path.is_file():
        return False
    marker = read_json(path)
    return (
        marker.get("schema_version") == 1
        and marker.get("runner") == "finalize-work"
        and marker.get("implementation_commit") == build.get("implementation_commit")
        and marker.get("source_hash") == build.get("approved_source_hash")
    )


def timing_phase_passed(audit_dir: Path, phase: str) -> bool:
    path = audit_dir / "timing.json"
    if not path.is_file():
        return False
    data = read_json(path)
    entries = data.get("entries")
    return isinstance(entries, list) and any(
        isinstance(item, dict)
        and item.get("phase") == phase
        and item.get("status") == "pass"
        for item in entries
    )


def running_timing_id(audit_dir: Path, phase: str) -> str | None:
    path = audit_dir / "timing.json"
    if not path.is_file():
        return None
    data = read_json(path)
    entries = data.get("entries")
    if not isinstance(entries, list):
        raise SystemExit("timing audit entries 必须是数组。")
    matches = [
        str(item.get("id"))
        for item in entries
        if isinstance(item, dict)
        and item.get("phase") == phase
        and item.get("status") == "running"
    ]
    if len(matches) > 1:
        raise SystemExit(f"timing 中存在多个 running {phase} 阶段。")
    return matches[0] if matches else None


def ensure_timing_running(
    script_dir: Path,
    audit_dir: Path,
    phase: str,
    *,
    reuse_pass: bool,
) -> None:
    if running_timing_id(audit_dir, phase) or (
        reuse_pass and timing_phase_passed(audit_dir, phase)
    ):
        return
    timing(script_dir, audit_dir, "start", "--phase", phase, "--kind", "final")


def finish_running_timing(
    script_dir: Path,
    audit_dir: Path,
    phase: str,
    status: str,
    reason: str | None = None,
) -> None:
    entry_id = running_timing_id(audit_dir, phase)
    if not entry_id:
        return
    args = ["--id", entry_id, "--status", status]
    if reason:
        args.extend(["--reason", reason])
    timing(script_dir, audit_dir, "finish", *args)


def write_finalization_marker(
    audit_dir: Path, build_root: Path, build: dict, checks: list[str], framework_root: Path
) -> None:
    semantic_checks = [
        name
        for name in checks
        if name not in COMMAND_CHECKS
        and name != "browser-acceptance"
        and name not in LEGACY_BROWSER_CHECKS
    ]
    required_phases = ["currentness"]
    if any(name in COMMAND_CHECKS for name in checks):
        required_phases.append("final-validation")
    if "browser-acceptance" in checks or LEGACY_BROWSER_CHECKS & set(checks):
        required_phases.append("browser-acceptance")
    if semantic_checks:
        required_phases.append("semantic-validation")
    required_phases.extend(["landing", "documentation"])
    existing_judge_binding = None
    existing_verifier_binding = None
    marker_path = finalization_marker_path(audit_dir)
    if marker_path.is_file():
        existing = read_json(marker_path)
        if isinstance(existing.get("judge_binding"), dict):
            existing_judge_binding = existing["judge_binding"]
        if isinstance(existing.get("verifier_binding"), dict):
            existing_verifier_binding = existing["verifier_binding"]
    existing_updated_at = None
    if marker_path.is_file():
        existing_marker = read_json(marker_path)
        if (
            existing_marker.get("implementation_commit") == build.get("implementation_commit")
            and existing_marker.get("source_hash") == build.get("approved_source_hash")
        ):
            existing_updated_at = existing_marker.get("updated_at")
    write_json(
        marker_path,
        {
            "schema_version": 1,
            "runner": "finalize-work",
            "implementation_commit": build.get("implementation_commit"),
            "source_hash": build.get("approved_source_hash"),
            "required_timing_phases": required_phases,
            "allowed_limited_timing_phases": [],
            "semantic_checks": semantic_checks,
            "framework_revision": os.environ.get("PMAI_FRAMEWORK_REVISION", "").strip()
            or git_revision(framework_root),
            "framework_clean": git_clean(framework_root),
            "consumer_revision": git_revision(build_root),
            "judge_binding": existing_judge_binding
            or {"status": "not_attached", "evidence_digest": None, "run_id": None},
            "verifier_binding": existing_verifier_binding
            or {"status": "not_attached", "run_id": None},
            "updated_at": existing_updated_at or now_iso(),
        },
    )


def update_verifier_binding(
    audit_dir: Path,
    build: dict,
    args: argparse.Namespace,
) -> dict:
    marker_path = finalization_marker_path(audit_dir)
    marker = read_json(marker_path)
    existing = marker.get("verifier_binding")
    if (
        isinstance(existing, dict)
        and existing.get("status") in {"pass", "degraded"}
        and existing.get("implementation_commit") == build.get("implementation_commit")
        and existing.get("source_hash") == build.get("approved_source_hash")
    ):
        return existing
    backend = args.agent_backend or "main-fallback"
    try:
        validate_backend(backend)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    host = args.agent_host or "unknown"
    if backend == "main-fallback" and not args.agent_host:
        host = "main-controller"
    fallback_reason = args.agent_reason or "child/external agent unavailable; main controller fallback"
    receipt = build_receipt(
        role="verifier",
        backend=backend,
        run_id=args.agent_run_id or new_run_id("verifier"),
        implementation_commit=str(build.get("implementation_commit") or ""),
        source_hash=str(build.get("approved_source_hash") or ""),
        host=host,
        model=args.agent_model or "runtime",
        status="degraded" if backend == "main-fallback" else "pass",
        reason=fallback_reason if backend == "main-fallback" else None,
    )
    marker["verifier_binding"] = receipt
    marker["updated_at"] = now_iso()
    write_json(marker_path, marker)
    return receipt


def ensure_audit_binding(
    script_dir: Path,
    build_root: Path,
    audit_dir: Path,
    verifier: dict,
) -> None:
    binding_path = audit_dir / "audit-binding.json"
    if binding_path.is_file():
        binding = read_json(binding_path)
        finalize = binding.get("finalize") or {}
        result = run(
            [
                sys.executable,
                str(script_dir / "finalize-audit-binding.py"),
                "verify",
                "--binding",
                str(binding_path),
                "--consumer-root",
                str(build_root),
                "--pre-landing",
            ],
            cwd=build_root,
            capture=True,
        )
        if (
            result.returncode == 0
            and (binding.get("judge") or {}).get("status") == "pass"
            and finalize.get("implementation_commit") == verifier.get("implementation_commit")
            and finalize.get("source_hash") == verifier.get("source_hash")
        ):
            return
    audit_rel = audit_dir.relative_to(build_root).as_posix()
    command = [
        sys.executable,
        str(script_dir / "finalize-audit-binding.py"),
        "bind",
        "--consumer-root",
        str(build_root),
        "--audit-dir",
        audit_rel,
        "--framework-root",
        str(script_dir.parent),
        "--runner-run-id",
        str(verifier["run_id"]),
        "--runner-role",
        "verifier",
        "--runner-backend",
        str(verifier["backend"]),
        "--pre-landing",
        "--replace",
    ]
    result = run(command, cwd=build_root, capture=True)
    require_ok(result, "绑定 Verifier audit evidence")


def audit_binding_has_judge(
    script_dir: Path,
    build_root: Path,
    audit_dir: Path,
) -> bool:
    binding_path = audit_dir / "audit-binding.json"
    if not binding_path.is_file():
        return False
    result = run(
        [
            sys.executable,
            str(script_dir / "finalize-audit-binding.py"),
            "verify",
            "--binding",
            str(binding_path),
            "--consumer-root",
            str(build_root),
            "--pre-landing",
            "--require-judge",
        ],
        cwd=build_root,
        capture=True,
    )
    return result.returncode == 0


def allow_limited_timing_phase(audit_dir: Path, phase: str) -> None:
    path = finalization_marker_path(audit_dir)
    marker = read_json(path)
    phases = marker.setdefault("allowed_limited_timing_phases", [])
    if not isinstance(phases, list):
        raise SystemExit("finalize marker 的 allowed_limited_timing_phases 必须是数组。")
    if phase not in phases:
        phases.append(phase)
    write_json(path, marker)


def artifact_is_current(path: Path, build: dict) -> bool:
    if not path.is_file():
        return False
    artifact = read_json(path)
    return (
        artifact.get("implementation_commit") == build.get("implementation_commit")
        and artifact.get("source_hash") == build.get("approved_source_hash")
    )


def record_evidence(
    script_dir: Path,
    build_root: Path,
    module_dir: Path,
    name: str,
    artifact: Path,
    *,
    status: str = "pass",
) -> None:
    result = run(
        [
            sys.executable,
            str(script_dir / "build-contract.py"),
            "record-evidence",
            str(module_dir),
            "--name",
            name,
            "--status",
            status,
            "--artifact",
            str(artifact),
        ],
        cwd=build_root,
        capture=True,
    )
    require_ok(result, f"记录 {name} evidence")


def run_command_validation(
    args: argparse.Namespace,
    script_dir: Path,
    build_root: Path,
    module_dir: Path,
    audit_dir: Path,
    build: dict,
    needed: list[str],
) -> None:
    artifact_path = audit_dir / "final-validation.json"
    current_artifact = artifact_is_current(artifact_path, build)
    if current_artifact:
        artifact = read_json(artifact_path)
    else:
        artifact = {}
    needed_commands = [COMMAND_CHECKS[name] for name in needed]
    statuses = command_statuses(artifact)
    if args.retry_failed or not current_artifact or not set(needed_commands) <= set(statuses):
        selected_checks = list(
            dict.fromkeys(
                [
                    value
                    for value in artifact.get("requested_checks", [])
                    if value in COMMAND_CHECKS.values()
                ]
                + [
                    value
                    for value in sorted(statuses)
                    if value in COMMAND_CHECKS.values()
                ]
                + needed_commands
            )
        )
        command = [
            sys.executable,
            str(script_dir / "final-validation.py"),
            "--repo-root",
            str(build_root),
            "--module-dir",
            str(module_dir),
            "--audit",
            str(artifact_path),
        ]
        for check in selected_checks:
            command.extend(["--check", check])
        result = run(command, cwd=build_root)
        artifact = read_json(artifact_path)
        if result.returncode not in {0, 1}:
            raise SystemExit("final-validation runner 异常退出。")
    statuses = command_statuses(artifact)
    unresolved: list[str] = []
    limited: list[str] = []
    for name in needed:
        command_name = COMMAND_CHECKS[name]
        status = statuses.get(command_name)
        if status == "pass":
            record_evidence(script_dir, build_root, module_dir, name, artifact_path)
        elif (
            status in {"fail", "blocked"}
            and name in LIMITABLE_CHECKS
            and exception_allows(build, name, artifact)
        ):
            record_evidence(
                script_dir,
                build_root,
                module_dir,
                name,
                artifact_path,
                status="limited",
            )
            limited.append(name)
        elif status in {"fail", "blocked"}:
            unresolved.append(name)
        else:
            raise SystemExit(f"final-validation artifact 没有证明 {name} 已执行。")
    if limited and not unresolved:
        artifact["status"] = "limited"
        exception = build.get("audit_exception")
        artifact["pm_assessment"] = {
            "status": "limited",
            "accepted_checks": limited,
            "accepted_at": exception.get("accepted_at") if isinstance(exception, dict) else None,
            "reason": exception.get("reason") if isinstance(exception, dict) else None,
        }
        write_json(artifact_path, artifact)
        started = json.loads(
            timing(
                script_dir,
                audit_dir,
                "start",
                "--phase",
                "final-validation",
                "--kind",
                "final",
            )
        )
        timing(
            script_dir,
            audit_dir,
            "finish",
            "--id",
            started["id"],
            "--status",
            "limited",
            "--reason",
            "PM accepted bound test/typecheck limitations: " + ",".join(limited),
        )
        allow_limited_timing_phase(audit_dir, "final-validation")
    if unresolved:
        raise SystemExit(
            "final-validation 保留了真实失败："
            + "、".join(unresolved)
            + "。先修缺陷；若仅 tests/typecheck 属已知风险，由 PM 绑定当前 artifact 明确接受。"
        )


def run_browser_validation(
    args: argparse.Namespace,
    script_dir: Path,
    build_root: Path,
    module_dir: Path,
    audit_dir: Path,
    build: dict,
    needed: list[str],
) -> None:
    if not args.browser_manifest:
        raise SystemExit("本次需要 browser-acceptance，请提供 --browser-manifest。")
    manifest = Path(args.browser_manifest).expanduser()
    manifest = manifest.resolve() if manifest.is_absolute() else (build_root / manifest).resolve()
    artifact_path = audit_dir / "browser-acceptance.json"
    if artifact_is_current(artifact_path, build):
        artifact = read_json(artifact_path)
        if artifact.get("status") == "fail" and not args.retry_failed:
            raise SystemExit(
                "当前 implementation commit 已有失败的 browser-acceptance；"
                "先修缺陷并记录新 commit，或明确传 --retry-failed 重试瞬时故障。"
            )
    else:
        artifact = {}
    legacy = [name for name in needed if name in LEGACY_BROWSER_CHECKS]
    derived_missing = any(not (audit_dir / f"{name}.json").is_file() for name in legacy)
    if artifact.get("status") != "pass" or args.retry_failed or derived_missing:
        command = [
            sys.executable,
            str(script_dir / "browser-acceptance.py"),
            "--repo-root",
            str(build_root),
            "--module-dir",
            str(module_dir),
            "--manifest",
            str(manifest),
            "--audit",
            str(artifact_path),
        ]
        if args.browse_bin:
            command.extend(["--browse-bin", args.browse_bin])
        for name in legacy:
            command.extend(["--legacy-check", name])
        result = run(command, cwd=build_root)
        if result.returncode != 0:
            raise SystemExit("browser-acceptance 发现真实失败，已退出 10 分钟正常路径。")
    if legacy:
        # Old v4 contracts keep their check names; all derivatives are produced
        # by the same active browser chain and bind the same batch digest.
        for name in legacy:
            record_evidence(
                script_dir,
                build_root,
                module_dir,
                name,
                audit_dir / f"{name}.json",
            )
    else:
        record_evidence(
            script_dir, build_root, module_dir, "browser-acceptance", artifact_path
        )


def run_coverage_validation(
    args: argparse.Namespace,
    script_dir: Path,
    build_root: Path,
    module_dir: Path,
    audit_dir: Path,
) -> None:
    if not args.coverage_plan or not args.coverage_artifacts:
        return
    artifact_path = audit_dir / "coverage.json"
    command = [
        sys.executable,
        str(script_dir / "coverage-evidence.py"),
        "--repo-root",
        str(build_root),
        "--module-dir",
        str(module_dir),
        "--plan",
        args.coverage_plan,
        "--artifacts",
        args.coverage_artifacts,
        "--output",
        str(artifact_path),
    ]
    for check_id in args.coverage_confirm_state:
        command.extend(["--confirm-state", check_id])
    result = run(command, cwd=build_root)
    if result.returncode != 0:
        raise SystemExit("coverage 仍有机器差异或未确认状态，不能登记为通过。")
    record_evidence(
        script_dir, build_root, module_dir, "coverage", artifact_path
    )


def commit_finalization_state(
    build_root: Path, module_dir: Path, audit_dir: Path
) -> None:
    try:
        meta_rel = (module_dir / ".work-meta.json").relative_to(build_root).as_posix()
        audit_rel = audit_dir.relative_to(build_root).as_posix()
    except ValueError as exc:
        raise SystemExit("finalize 状态路径不在 build worktree 内。") from exc

    staged = run(
        ["git", "diff", "--cached", "--name-only"],
        cwd=build_root,
        capture=True,
    )
    require_ok(staged, "读取已暂存路径")
    staged_paths = staged.stdout.splitlines()
    unexpected = [
        path
        for path in staged_paths
        if path != meta_rel and not (path == audit_rel or path.startswith(f"{audit_rel}/"))
    ]
    if unexpected:
        raise SystemExit(
            "build worktree 已有不属于本次最终化的 staged 路径，拒绝混入验收提交："
            + "、".join(unexpected)
        )

    tracked_audit = run(
        ["git", "ls-files", "--", audit_rel],
        cwd=build_root,
        capture=True,
    )
    require_ok(tracked_audit, "读取已跟踪 audit 路径")
    audit_has_content = (
        bool(tracked_audit.stdout.strip())
        or any(path == audit_rel or path.startswith(f"{audit_rel}/") for path in staged_paths)
        or any(path.is_file() or path.is_symlink() for path in audit_dir.rglob("*"))
    )
    pathspecs = [meta_rel]
    if audit_has_content:
        pathspecs.append(audit_rel)

    added = run(
        ["git", "add", "-A", "--", *pathspecs],
        cwd=build_root,
        capture=True,
    )
    require_ok(added, "暂存最终化状态")
    changed = run(
        ["git", "diff", "--cached", "--quiet", "--", *pathspecs],
        cwd=build_root,
    )
    if changed.returncode == 0:
        return
    if changed.returncode != 1:
        raise SystemExit("无法判断最终化状态是否需要提交。")

    commit_env = os.environ.copy()
    commit_env["PMAI_ALLOW_MIXED_DELIVERY"] = "build-close"
    committed = run(
        [
            "git",
            "commit",
            "-m",
            f"build({module_dir.name}): record final acceptance",
            "--",
            *pathspecs,
        ],
        cwd=build_root,
        capture=True,
        env=commit_env,
    )
    require_ok(committed, "提交最终化状态")


def maybe_land(
    args: argparse.Namespace, script_dir: Path, main_root: Path, module_dir: Path
) -> int:
    if args.no_land:
        return 0
    land_env = os.environ.copy()
    land_env["PMAI_REQUIRE_FINAL_TIMING"] = "1"
    result = run(
        ["bash", str(script_dir / "close-work.sh"), str(module_dir)],
        cwd=main_root,
        env=land_env,
    )
    main_module = main_root / "docs" / "modules" / module_dir.name
    if result.returncode == 0 and module_dir != main_module and main_module.is_dir():
        print(f"FINALIZE_RESUME_MODULE={main_module}")
    return result.returncode


def finalize(args: argparse.Namespace) -> int:
    script_dir = Path(__file__).resolve().parent
    module_dir = Path(args.module_dir).expanduser().resolve()
    build_root = git_root(module_dir)
    main_root = main_repo_root(build_root)
    meta, build = build_state(module_dir)
    audit_dir = audit_dir_for(build_root, module_dir, build)
    audit_dir.mkdir(parents=True, exist_ok=True)
    try:
        state = normalize_work_contract(meta).lifecycle_state
    except WorkContractError as exc:
        raise SystemExit(str(exc)) from exc

    if state == "iterating":
        checks = final_checks(build)
        marker_path = finalization_marker_path(audit_dir)
        finalization = build.get("finalization")
        finalization_active = (
            isinstance(finalization, dict)
            and bool(finalization.get("requested_at"))
            and finalization.get("requested_commit") == build.get("implementation_commit")
        )
        resumable_attempt = marker_is_current(marker_path, build) and finalization_active
        if not resumable_attempt:
            finish_running_timing(
                script_dir,
                audit_dir,
                "semantic-validation",
                "fail",
                "implementation/source changed or PM feedback reset finalization",
            )
        if not (
            resumable_attempt
            and timing_phase_passed(audit_dir, "currentness")
        ):
            currentness_check(script_dir, build_root, module_dir, audit_dir)
        if not isinstance(finalization, dict) or not finalization.get("requested_at"):
            result = run(
                [
                    sys.executable,
                    str(script_dir / "build-contract.py"),
                    "request-finalization",
                    str(module_dir),
                ],
                cwd=build_root,
                capture=True,
            )
            require_ok(result, "记录 PM 定稿请求")
        _, build = build_state(module_dir)
        write_finalization_marker(audit_dir, build_root, build, checks, script_dir.parent)
        semantic_checks = [
            name
            for name in checks
            if name not in COMMAND_CHECKS
            and name != "browser-acceptance"
            and name not in LEGACY_BROWSER_CHECKS
        ]
        present = evidence_names(build)
        commands_needed = [name for name in checks if name in COMMAND_CHECKS and name not in present]
        if commands_needed:
            run_command_validation(
                args, script_dir, build_root, module_dir, audit_dir, build, commands_needed
            )
        _, build = build_state(module_dir)
        present = evidence_names(build)
        if "browser-acceptance" in checks and "browser-acceptance" not in present:
            run_browser_validation(
                args,
                script_dir,
                build_root,
                module_dir,
                audit_dir,
                build,
                ["browser-acceptance"],
            )
        _, build = build_state(module_dir)
        present = evidence_names(build)
        legacy_browser_needed = [
            name for name in checks if name in LEGACY_BROWSER_CHECKS and name not in present
        ]
        if legacy_browser_needed:
            legacy_browser_batch = [
                name for name in checks if name in LEGACY_BROWSER_CHECKS
            ]
            run_browser_validation(
                args,
                script_dir,
                build_root,
                module_dir,
                audit_dir,
                build,
                legacy_browser_batch,
            )
        _, build = build_state(module_dir)
        present = evidence_names(build)
        if "coverage" in checks and "coverage" not in present:
            run_coverage_validation(
                args, script_dir, build_root, module_dir, audit_dir
            )
        _, build = build_state(module_dir)
        missing = [name for name in checks if name not in evidence_names(build)]
        if missing and any(name in semantic_checks for name in missing):
            ensure_timing_running(
                script_dir,
                audit_dir,
                "semantic-validation",
                reuse_pass=resumable_attempt,
            )
        _, build = build_state(module_dir)
        verifier = update_verifier_binding(audit_dir, build, args)
        ensure_audit_binding(script_dir, build_root, audit_dir, verifier)
        missing = [name for name in checks if name not in evidence_names(build)]
        if missing:
            print(
                "机械验收已完成；仍需 Verifier/Judge 完成并记录：" + "、".join(missing),
                file=sys.stderr,
            )
            return 3
        if semantic_checks:
            if not audit_binding_has_judge(script_dir, build_root, audit_dir):
                ensure_timing_running(
                    script_dir,
                    audit_dir,
                    "semantic-validation",
                    reuse_pass=resumable_attempt,
                )
                print(
                    "机械与语义证据已生成；仍需独立 Judge 绑定当前 evidence digest。",
                    file=sys.stderr,
                )
                return 3
            ensure_timing_running(
                script_dir,
                audit_dir,
                "semantic-validation",
                reuse_pass=resumable_attempt,
            )
        result = run(
            [
                sys.executable,
                str(script_dir / "build-contract.py"),
                "review-ready",
                str(module_dir),
            ],
            cwd=build_root,
            capture=True,
        )
        require_ok(result, "review-ready")
        if semantic_checks:
            finish_running_timing(
                script_dir, audit_dir, "semantic-validation", "pass"
            )
        result = run(
            [
                sys.executable,
                str(script_dir / "build-contract.py"),
                "accept",
                str(module_dir),
            ],
            cwd=build_root,
            capture=True,
        )
        require_ok(result, "accept")
        state = "final_check"

    if state == "final_check":
        commit_finalization_state(build_root, module_dir, audit_dir)
    if state in {"final_check", "landed", "documenting"}:
        return maybe_land(args, script_dir, main_root, module_dir)
    raise SystemExit(f"当前 lifecycle={state or '<empty>'}，finalize runner 无可执行步骤。")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--module-dir", required=True)
    result.add_argument("--browser-manifest")
    result.add_argument("--browse-bin")
    result.add_argument("--coverage-plan")
    result.add_argument("--coverage-artifacts")
    result.add_argument("--coverage-confirm-state", action="append", default=[])
    result.add_argument("--agent-backend", choices=["child", "external", "main-fallback"])
    result.add_argument("--agent-run-id")
    result.add_argument("--agent-host")
    result.add_argument("--agent-model")
    result.add_argument("--agent-reason")
    result.add_argument("--retry-failed", action="store_true")
    result.add_argument("--no-land", action="store_true")
    return result


def main(argv: list[str] | None = None) -> int:
    try:
        return finalize(parser().parse_args(argv))
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise


if __name__ == "__main__":
    raise SystemExit(main())
