#!/usr/bin/env python3
"""Bind an existing finalize audit to current framework and consumer revisions."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _lib.finalize_audit import (  # noqa: E402
    binding_digest,
    digest,
    evidence_digest,
    git_clean,
    git_revision,
    read_object,
    resolve_audit_dir,
    tool_file_hashes,
    validate_finalize_audit,
)
from _lib.agent_roles import (  # noqa: E402
    independent_for_backend,
    validate_backend,
    validate_receipt,
    validate_role,
)


TOOL_FILES = [
    "scripts/finalize-audit-binding.py",
    "scripts/finalize-audit-readonly-judge.py",
    "scripts/finalize-work.py",
    "scripts/_lib/agent_roles.py",
    "scripts/_lib/finalize_audit.py",
]


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def write_json(path: Path, value: dict) -> None:
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def framework_root(args: argparse.Namespace) -> Path:
    raw = args.framework_root or os.environ.get("PMAI_FRAMEWORK_ROOT")
    return Path(raw).expanduser().resolve() if raw else SCRIPT_DIR.parent.resolve()


def command_bind(args: argparse.Namespace) -> int:
    consumer_root = Path(args.consumer_root).expanduser().resolve()
    audit_dir = resolve_audit_dir(consumer_root, args.audit_dir)
    output = Path(args.output).expanduser().resolve() if args.output else audit_dir / "audit-binding.json"
    if output.parent != audit_dir:
        raise SystemExit("绑定输出必须位于 audit 目录内。")
    if output.exists() and not args.replace:
        raise SystemExit(f"绑定文件已存在：{output}；如需重建请传 --replace。")

    runner_role = args.runner_role or "verifier"
    runner_backend = args.runner_backend or "external"
    try:
        validate_role(runner_role, expected="verifier")
        validate_backend(runner_backend)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    audit = validate_finalize_audit(audit_dir, complete=not args.pre_landing)
    if args.pre_landing:
        try:
            validate_receipt(
                audit["marker"].get("verifier_binding"),
                expected_role="verifier",
                implementation_commit=audit["implementation_commit"],
                source_hash=audit["source_hash"],
                require_pass=True,
            )
        except ValueError as exc:
            raise SystemExit(str(exc)) from exc
    if args.pre_landing:
        verifier = audit["marker"].get("verifier_binding")
        if not isinstance(verifier, dict):
            raise SystemExit("pre-landing binding 缺少 Verifier receipt。")
        if verifier.get("status") not in {"pass", "degraded"}:
            raise SystemExit("pre-landing binding 的 Verifier 尚未完成。")
        if verifier.get("role") != runner_role or verifier.get("backend") != runner_backend:
            raise SystemExit("pre-landing binding 的 Verifier role/backend 不一致。")
        if args.runner_run_id and verifier.get("run_id") != args.runner_run_id:
            raise SystemExit("pre-landing binding 的 Verifier run_id 不一致。")
    output_relative = output.relative_to(consumer_root).as_posix()
    framework = framework_root(args)
    framework_revision = git_revision(framework)
    consumer_revision = git_revision(consumer_root)
    tools = tool_file_hashes(framework, TOOL_FILES)
    files = audit["file_hashes"]
    core = {
        "schema_version": 1,
        "kind": "finalize-audit-binding",
        "audit_dir": audit_dir.relative_to(consumer_root).as_posix(),
        "finalize": {
            "implementation_commit": audit["implementation_commit"],
            "source_hash": audit["source_hash"],
            "marker_digest": digest(audit["marker"]),
        },
        "provenance": {
            "framework_revision": framework_revision,
            "framework_clean": git_clean(framework),
            "tool_files": tools,
            "tool_digest": digest({"files": tools}),
            "consumer_revision": consumer_revision,
            "consumer_clean_at_bind": git_clean(consumer_root, [output_relative]),
            "bound_at": now_iso(),
            "runner_run_id": args.runner_run_id,
            "runner_role": runner_role,
            "runner_backend": runner_backend,
            "runner_independent": independent_for_backend(runner_backend),
        },
        "evidence": {
            "files": files,
            "digest": evidence_digest(files),
        },
        "judge": {
            "status": "pending",
            "run_id": None,
            "evidence_digest": None,
        },
        "phase": "pre-landing" if args.pre_landing else "complete",
    }
    write_json(output, {**core, "digest": binding_digest(core)})
    print(json.dumps({"status": "pass", "path": str(output), "digest": binding_digest(core)}, ensure_ascii=False))
    return 0


def command_attach_judge(args: argparse.Namespace) -> int:
    binding_path = Path(args.binding).expanduser().resolve()
    binding = read_object(binding_path, "audit binding")
    recorded_digest = binding.get("digest")
    if recorded_digest != binding_digest(binding):
        raise SystemExit("audit binding digest 不一致。")
    if args.consumer_root:
        consumer_root = Path(args.consumer_root).expanduser().resolve()
        audit_dir = resolve_audit_dir(consumer_root, str(binding.get("audit_dir") or ""))
        audit = validate_finalize_audit(
            audit_dir,
            complete=binding.get("phase") != "pre-landing",
        )
        expected_files = (binding.get("evidence") or {}).get("files")
        expected_digest = (binding.get("evidence") or {}).get("digest")
        if expected_files != audit["file_hashes"] or expected_digest != evidence_digest(audit["file_hashes"]):
            raise SystemExit("Judge attach 前发现 audit evidence 已漂移。")
    judge = read_object(Path(args.judge_json).expanduser().resolve(), "Judge 结果")
    provenance = judge.get("provenance")
    if judge.get("pass") is not True or not isinstance(provenance, dict):
        raise SystemExit("Judge 结果必须是 pass=true 且包含 provenance。")
    judge_role = provenance.get("role", judge.get("role", "judge"))
    judge_backend = provenance.get("backend", judge.get("backend", "external"))
    try:
        validate_role(judge_role, expected="judge")
        validate_backend(judge_backend)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    run_id = provenance.get("run_id")
    if not isinstance(run_id, str) or not run_id.strip():
        raise SystemExit("Judge provenance.run_id 不能为空。")
    for field in ("host", "model", "framework_revision", "tool_sha256"):
        if not isinstance(provenance.get(field), str) or not provenance[field].strip():
            raise SystemExit(f"Judge provenance.{field} 不能为空。")
    runner_run_id = (binding.get("provenance") or {}).get("runner_run_id")
    if runner_run_id and runner_run_id == run_id:
        raise SystemExit("Judge run_id 不能复用 Runner run_id。")
    expected = (binding.get("evidence") or {}).get("digest")
    if judge.get("evidence_digest") != expected:
        raise SystemExit("Judge evidence_digest 未绑定当前 audit evidence digest。")
    marker = read_object(binding_path.parent / "finalize-run.json", "finalize marker")
    semantic_checks = marker.get("semantic_checks") or []
    if not isinstance(semantic_checks, list) or any(
        not isinstance(item, str) or not item.strip() for item in semantic_checks
    ):
        raise SystemExit("finalize marker.semantic_checks 不合法。")
    if semantic_checks:
        checks = judge.get("checks")
        if not isinstance(checks, list) or any(not isinstance(item, dict) for item in checks):
            raise SystemExit("语义 Judge 结果缺少 checks 数组。")
        by_name = {str(item.get("name")): item for item in checks}
        if set(by_name) != set(semantic_checks):
            raise SystemExit("语义 Judge checks 未精确覆盖当前 semantic_checks。")
        if any(by_name[name].get("status") != "pass" for name in semantic_checks):
            raise SystemExit("语义 Judge 存在未通过的 semantic check。")
    semantic_judge_path = binding_path.parent / "semantic-judge.json"
    write_json(semantic_judge_path, judge)
    updated = dict(binding)
    updated["judge"] = {
        "status": "pass",
        "run_id": run_id,
        "host": provenance.get("host"),
        "model": provenance.get("model"),
        "framework_revision": provenance.get("framework_revision"),
        "tool_sha256": provenance.get("tool_sha256"),
        "evidence_digest": judge.get("evidence_digest"),
        "role": judge_role,
        "backend": judge_backend,
        "independent": independent_for_backend(judge_backend),
        "reason": judge.get("reason"),
        "attached_at": now_iso(),
    }
    updated["digest"] = binding_digest(updated)
    write_json(binding_path, updated)
    if args.module_dir and semantic_checks:
        if not args.consumer_root:
            raise SystemExit("传入 module-dir 时必须同时提供 consumer-root。")
        module_dir = Path(args.module_dir).expanduser().resolve()
        try:
            module_dir.relative_to(Path(args.consumer_root).expanduser().resolve())
        except ValueError as exc:
            raise SystemExit("module-dir 必须位于 consumer-root 内。") from exc
        for check in semantic_checks:
            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_DIR / "build-contract.py"),
                    "record-evidence",
                    str(module_dir),
                    "--name",
                    check,
                    "--status",
                    "pass",
                    "--artifact",
                    str(semantic_judge_path),
                ],
                cwd=module_dir,
                text=True,
                capture_output=True,
                check=False,
            )
            if result.returncode != 0:
                detail = result.stderr.strip() or result.stdout.strip()
                raise SystemExit(f"记录语义 Judge evidence 失败：{detail}")
    print(json.dumps({"status": "pass", "path": str(binding_path), "digest": updated["digest"]}, ensure_ascii=False))
    return 0


def command_verify(args: argparse.Namespace) -> int:
    binding_path = Path(args.binding).expanduser().resolve()
    binding = read_object(binding_path, "audit binding")
    if binding.get("digest") != binding_digest(binding):
        raise SystemExit("audit binding digest 不一致。")
    consumer_root = Path(args.consumer_root).expanduser().resolve()
    audit_dir = resolve_audit_dir(consumer_root, str(binding.get("audit_dir") or ""))
    audit = validate_finalize_audit(audit_dir, complete=not args.pre_landing)
    files = audit["file_hashes"]
    evidence = binding.get("evidence")
    if not isinstance(evidence, dict) or evidence.get("files") != files:
        raise SystemExit("audit 文件快照已漂移。")
    if evidence.get("digest") != evidence_digest(files):
        raise SystemExit("audit evidence digest 不一致。")
    finalize = binding.get("finalize")
    if not isinstance(finalize, dict) or finalize.get("implementation_commit") != audit["implementation_commit"] or finalize.get("source_hash") != audit["source_hash"]:
        raise SystemExit("绑定的 finalize 身份已漂移。")
    if args.require_judge and (binding.get("judge") or {}).get("status") != "pass":
        raise SystemExit("audit binding 尚未附加通过的独立 Judge。")
    judge = binding.get("judge") or {}
    if judge.get("status") == "pass" and judge.get("evidence_digest") != evidence.get("digest"):
        raise SystemExit("Judge evidence_digest 与当前 audit evidence digest 不一致。")
    print(json.dumps({"status": "pass", "judge": (binding.get("judge") or {}).get("status"), "digest": binding["digest"]}, ensure_ascii=False))
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    bind = sub.add_parser("bind")
    bind.add_argument("--consumer-root", required=True)
    bind.add_argument("--audit-dir", required=True)
    bind.add_argument("--framework-root")
    bind.add_argument("--runner-run-id")
    bind.add_argument("--runner-role")
    bind.add_argument("--runner-backend")
    bind.add_argument("--pre-landing", action="store_true")
    bind.add_argument("--output")
    bind.add_argument("--replace", action="store_true")
    bind.set_defaults(func=command_bind)
    attach = sub.add_parser("attach-judge")
    attach.add_argument("--binding", required=True)
    attach.add_argument("--judge-json", required=True)
    attach.add_argument("--module-dir")
    attach.add_argument("--consumer-root")
    attach.set_defaults(func=command_attach_judge)
    verify = sub.add_parser("verify")
    verify.add_argument("--binding", required=True)
    verify.add_argument("--consumer-root", required=True)
    verify.add_argument("--require-judge", action="store_true")
    verify.add_argument("--pre-landing", action="store_true")
    verify.set_defaults(func=command_verify)
    return result


if __name__ == "__main__":
    try:
        parsed = parser().parse_args()
        raise SystemExit(parsed.func(parsed))
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
