#!/usr/bin/env python3
"""Create an explicit recovery checkpoint for legacy active work.

The build command rebases a v1-v4 build's future evidence/hash chain.  The
design command preserves an existing design round and returns an old ready
contract to designing.  Neither command changes module documents or creates a
Product Proposal.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

SCRIPTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS_DIR))

from _lib.legacy_recovery import (  # noqa: E402
    ACTIVE_DESIGN_STATES,
    RECOVERY_SCHEMA_VERSION,
    replay_original_build_hash,
    validate_legacy_recovery,
)


CURRENT_SOURCE_HASH_VERSION = 2
READY_FIELDS = (
    "approved_source_hash",
    "design_checkpoint_commit",
    "approved_target",
)


def _load_context_module():
    name = "pmai_context_pack_recovery"
    spec = importlib.util.spec_from_file_location(name, SCRIPTS_DIR / "context-pack.py")
    if spec is None or spec.loader is None:
        raise SystemExit("无法加载 context-pack.py。")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _read_meta(module_dir: Path) -> dict[str, Any]:
    path = module_dir / ".work-meta.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"缺少工作状态文件：{path}") from exc
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f"无法读取工作状态文件：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(".work-meta.json 顶层必须是对象。")
    return value


def _repo_root(module_dir: Path) -> Path:
    result = subprocess.run(
        ["git", "-C", str(module_dir), "rev-parse", "--show-toplevel"],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise SystemExit(result.stderr.strip() or "无法定位消费仓 Git 根目录。")
    return Path(result.stdout.strip()).resolve()


def _git(repo_root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or f"Git 命令失败：{' '.join(args)}")
    return result.stdout.strip()


def _write_meta(path: Path, meta: dict[str, Any]) -> None:
    if path.is_symlink():
        raise SystemExit(".work-meta.json 不能是 symlink。")
    temp = path.with_name(f".{path.name}.legacy-recovery.tmp")
    temp.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temp.replace(path)


def _working_source_pack(repo_root: Path, module_dir: Path, meta: dict[str, Any]) -> dict[str, Any]:
    context = _load_context_module()
    sources = context.collect_sources(repo_root, module_dir, meta, None)
    version = context.source_hash_version(meta)
    _, input_hashes, source_hash, scope = context.source_records(repo_root, sources, version)
    return {
        "source_hash": source_hash,
        "source_scope": scope,
        "source_file_hashes": {path: input_hashes[path] for path in scope},
        "source_hash_version": version,
    }


def accept(args: argparse.Namespace) -> int:
    module_dir = Path(args.module_dir).expanduser().resolve()
    repo_root = _repo_root(module_dir)
    meta_path = module_dir / ".work-meta.json"
    meta = _read_meta(module_dir)
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit("只能恢复已有 active build；当前模块没有 build contract。")
    try:
        version = int(build.get("contract_version"))
    except (TypeError, ValueError) as exc:
        raise SystemExit("build.contract_version 不合法。") from exc
    if version >= 5:
        raise SystemExit("legacy recovery 只适用于 v1-v4 build contract。")
    lifecycle = build.get("lifecycle_state") or meta.get("lifecycle_state")
    if lifecycle not in {"building", "iterating", "final_check"}:
        raise SystemExit(f"当前 lifecycle={lifecycle or '<empty>'}，不能恢复 active build。")
    if meta.get("legacy_recovery") is not None:
        raise SystemExit("当前模块已经存在 legacy recovery 记录；禁止重复恢复。")

    pack = _working_source_pack(repo_root, module_dir, meta)
    checkpoint = _git(repo_root, "rev-parse", "HEAD")
    original_design_hash = str(meta.get("approved_source_hash") or "").strip()
    original_hash = str(build.get("approved_source_hash") or "").strip()
    if len(original_design_hash) != 64 or len(original_hash) != 64:
        raise SystemExit("旧 build 缺少合法 approved_source_hash，不能安全恢复。")
    original_deltas = build.get("accepted_deltas") or []
    if not isinstance(original_deltas, list) or any(
        not isinstance(delta, dict) for delta in original_deltas
    ):
        raise SystemExit("旧 build 的 accepted_deltas 不是合法对象数组，不能安全恢复。")
    replayed_hash = replay_original_build_hash(original_design_hash, original_deltas)

    # Validate the legacy record shape before writing, while allowing the
    # current v1-v4 contract to be the source of truth for lifecycle/version.
    recovery = {
        "schema_version": RECOVERY_SCHEMA_VERSION,
        "kind": "active-build",
        "status": "accepted",
        "confirmed_by": args.confirmed_by.strip(),
        "confirmed_at": args.confirmed_at.strip(),
        "reason": args.reason.strip(),
        "checkpoint_commit": checkpoint,
        "authority_source_hash": pack["source_hash"],
        "authority_source_scope": pack["source_scope"],
        "authority_source_file_hashes": pack["source_file_hashes"],
        "original_design_approved_source_hash": original_design_hash,
        "original_build_approved_source_hash": original_hash,
        "original_replayed_build_approved_source_hash": replayed_hash,
        "original_hash_chain_state": (
            "consistent" if replayed_hash == original_hash else "mismatch"
        ),
        "reconciled_build_approved_source_hash": pack["source_hash"],
        "original_contract_version": version,
        "original_accepted_delta_count": len(original_deltas),
        "original_accepted_deltas": original_deltas,
    }
    try:
        validate_legacy_recovery({**meta, "legacy_recovery": recovery})
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    meta["approved_source_hash"] = pack["source_hash"]
    build["approved_source_hash"] = pack["source_hash"]
    # The old chain remains auditable in legacy_recovery.  The active contract
    # starts a new chain at the explicitly confirmed authority checkpoint.
    build["accepted_deltas"] = []
    meta["legacy_recovery"] = recovery
    _write_meta(meta_path, meta)
    print(
        json.dumps(
            {
                "status": "recovered",
                "module": module_dir.relative_to(repo_root).as_posix(),
                "checkpoint_commit": checkpoint,
                "authority_source_hash": pack["source_hash"],
                "original_design_approved_source_hash": original_design_hash,
                "original_build_approved_source_hash": original_hash,
                "original_replayed_build_approved_source_hash": replayed_hash,
                "original_hash_chain_state": recovery["original_hash_chain_state"],
                "reconciled_build_approved_source_hash": pack["source_hash"],
                "original_contract_version": version,
            },
            ensure_ascii=False,
        )
    )
    return 0


def accept_design(args: argparse.Namespace) -> int:
    module_dir = Path(args.module_dir).expanduser().resolve()
    repo_root = _repo_root(module_dir)
    meta_path = module_dir / ".work-meta.json"
    meta = _read_meta(module_dir)
    if meta.get("status") != "active":
        raise SystemExit("只能恢复 status=active 的旧 design。")
    if isinstance(meta.get("build"), dict):
        raise SystemExit("当前模块已经有 build contract；请使用 active build 恢复入口。")
    lifecycle = meta.get("lifecycle_state")
    if lifecycle not in ACTIVE_DESIGN_STATES:
        raise SystemExit(f"当前 lifecycle={lifecycle or '<empty>'}，不能恢复 active design。")
    if meta.get("legacy_recovery") is not None:
        raise SystemExit("当前模块已经存在 legacy recovery 记录；禁止重复恢复。")

    # Design resumes under the current scoped hash contract.  The old ready
    # approval remains in the recovery audit record, but no longer authorizes a
    # build after the PM explicitly sends the work back to design.
    recovery_meta = dict(meta)
    recovery_meta["lifecycle_state"] = "designing"
    recovery_meta["source_hash_version"] = CURRENT_SOURCE_HASH_VERSION
    recovery_meta.pop("stage", None)
    for key in READY_FIELDS:
        recovery_meta.pop(key, None)
    pack = _working_source_pack(repo_root, module_dir, recovery_meta)
    checkpoint = _git(repo_root, "rev-parse", "HEAD")
    original_ready_contract = {
        key: meta[key]
        for key in (*READY_FIELDS, "source_hash_version", "design_revision")
        if key in meta
    }
    recovery = {
        "schema_version": RECOVERY_SCHEMA_VERSION,
        "kind": "active-design",
        "status": "accepted",
        "confirmed_by": args.confirmed_by.strip(),
        "confirmed_at": args.confirmed_at.strip(),
        "reason": args.reason.strip(),
        "checkpoint_commit": checkpoint,
        "authority_source_hash": pack["source_hash"],
        "authority_source_scope": pack["source_scope"],
        "authority_source_file_hashes": pack["source_file_hashes"],
        "original_lifecycle_state": lifecycle,
        "resumed_lifecycle_state": "designing",
        "original_ready_contract": original_ready_contract,
    }
    recovery_meta["legacy_recovery"] = recovery
    try:
        validate_legacy_recovery(recovery_meta)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    _write_meta(meta_path, recovery_meta)
    print(
        json.dumps(
            {
                "status": "recovered",
                "kind": "active-design",
                "module": module_dir.relative_to(repo_root).as_posix(),
                "checkpoint_commit": checkpoint,
                "authority_source_hash": pack["source_hash"],
                "original_lifecycle_state": lifecycle,
                "resumed_lifecycle_state": "designing",
            },
            ensure_ascii=False,
        )
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    accept_parser = sub.add_parser("accept", help="记录 PM 确认并恢复一个旧 active build")
    accept_parser.add_argument("module_dir")
    accept_parser.add_argument("--confirmed-by", required=True)
    accept_parser.add_argument("--confirmed-at", required=True)
    accept_parser.add_argument("--reason", required=True)
    accept_parser.set_defaults(func=accept)
    design_parser = sub.add_parser(
        "accept-design", help="记录 PM 确认并恢复一个旧 active design"
    )
    design_parser.add_argument("module_dir")
    design_parser.add_argument("--confirmed-by", required=True)
    design_parser.add_argument("--confirmed-at", required=True)
    design_parser.add_argument("--reason", required=True)
    design_parser.set_defaults(func=accept_design)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise


if __name__ == "__main__":
    raise SystemExit(main())
