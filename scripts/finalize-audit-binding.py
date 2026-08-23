#!/usr/bin/env python3
"""Bind an existing finalize audit to current framework and consumer revisions."""

from __future__ import annotations

import argparse
import json
import os
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


TOOL_FILES = [
    "scripts/finalize-audit-binding.py",
    "scripts/finalize-audit-readonly-judge.py",
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

    audit = validate_finalize_audit(audit_dir)
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
    judge = read_object(Path(args.judge_json).expanduser().resolve(), "Judge 结果")
    provenance = judge.get("provenance")
    if judge.get("pass") is not True or not isinstance(provenance, dict):
        raise SystemExit("Judge 结果必须是 pass=true 且包含 provenance。")
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
    updated = dict(binding)
    updated["judge"] = {
        "status": "pass",
        "run_id": run_id,
        "host": provenance.get("host"),
        "model": provenance.get("model"),
        "framework_revision": provenance.get("framework_revision"),
        "tool_sha256": provenance.get("tool_sha256"),
        "evidence_digest": judge.get("evidence_digest"),
        "reason": judge.get("reason"),
        "attached_at": now_iso(),
    }
    updated["digest"] = binding_digest(updated)
    write_json(binding_path, updated)
    print(json.dumps({"status": "pass", "path": str(binding_path), "digest": updated["digest"]}, ensure_ascii=False))
    return 0


def command_verify(args: argparse.Namespace) -> int:
    binding_path = Path(args.binding).expanduser().resolve()
    binding = read_object(binding_path, "audit binding")
    if binding.get("digest") != binding_digest(binding):
        raise SystemExit("audit binding digest 不一致。")
    consumer_root = Path(args.consumer_root).expanduser().resolve()
    audit_dir = resolve_audit_dir(consumer_root, str(binding.get("audit_dir") or ""))
    audit = validate_finalize_audit(audit_dir)
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
    bind.add_argument("--output")
    bind.add_argument("--replace", action="store_true")
    bind.set_defaults(func=command_bind)
    attach = sub.add_parser("attach-judge")
    attach.add_argument("--binding", required=True)
    attach.add_argument("--judge-json", required=True)
    attach.set_defaults(func=command_attach_judge)
    verify = sub.add_parser("verify")
    verify.add_argument("--binding", required=True)
    verify.add_argument("--consumer-root", required=True)
    verify.add_argument("--require-judge", action="store_true")
    verify.set_defaults(func=command_verify)
    return result


if __name__ == "__main__":
    try:
        parsed = parser().parse_args()
        raise SystemExit(parsed.func(parsed))
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
