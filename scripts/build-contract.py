#!/usr/bin/env python3
"""Write and validate the build contract stored in module .work-meta.json.

The contract is the handoff between /pmai-build and /pmai-build-close. It
records the choices PM made before implementation, so close does not infer the
landing path from the current shell cwd or branch shape.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


VALID_MODES = {"worktree", "main"}
VALID_EXECUTORS = {"claude-code", "codex", "cursor-agent", "gemini", "manual"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def meta_path(module_dir: Path) -> Path:
    return module_dir / ".work-meta.json"


def default_meta(module_dir: Path, branch: str | None = None) -> dict:
    module_name = module_dir.name
    branch_value = branch.strip() if branch else ""
    return {
        "id": f"work-{module_name}",
        "name": module_name,
        "branch": branch_value,
        "stage": 1,
        "status": "active",
        "created_at": now_iso(),
    }


def read_meta(module_dir: Path) -> dict:
    path = meta_path(module_dir)
    if not path.exists():
        raise SystemExit(f"缺少模块工作状态文件: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f".work-meta.json 不是合法 JSON: {path}: {exc}") from exc


def write_meta(module_dir: Path, meta: dict) -> None:
    path = meta_path(module_dir)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def optional(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    return value or None


def validate_mode_executor(mode: str, executor: str | None) -> None:
    if mode not in VALID_MODES:
        raise SystemExit(f"build.mode 必须是 {' / '.join(sorted(VALID_MODES))}: {mode}")
    if executor and executor not in VALID_EXECUTORS:
        raise SystemExit(
            f"build.executor 必须是 {' / '.join(sorted(VALID_EXECUTORS))}: {executor}"
        )


def cmd_start(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    path = meta_path(module_dir)
    if path.exists():
        meta = read_meta(module_dir)
    else:
        module_dir.mkdir(parents=True, exist_ok=True)
        meta = default_meta(module_dir, args.branch)

    mode = args.mode
    executor = args.executor
    validate_mode_executor(mode, executor)

    branch = optional(args.branch) or ("main" if mode == "main" else None)
    worktree = optional(args.worktree)
    if mode == "worktree" and not branch:
        raise SystemExit("worktree 模式必须记录 build.branch")
    if mode == "main":
        worktree = None

    build = {
        "anchor": args.anchor,
        "mode": mode,
        "executor": executor,
        "branch": branch,
        "worktree": worktree,
        "baseline_sha": optional(args.baseline_sha),
        "audit_dir": optional(args.audit_dir),
        "started_at": now_iso(),
        "implementation_commit": None,
        "pm_accepted_at": None,
    }

    meta["status"] = "active"
    meta["stage"] = 2
    meta["branch"] = branch or meta.get("branch", "")
    if worktree is not None:
        meta["worktree"] = worktree
    elif mode == "main":
        meta["worktree"] = None
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def require_build(meta: dict) -> dict:
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit("缺少 build 合同：请先由 /pmai-build 记录执行方式、执行器和验收结果，再收尾。")
    return build


def cmd_commit(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    commit = optional(args.implementation_commit)
    if not commit:
        raise SystemExit("必须提供 implementation_commit")
    build["implementation_commit"] = commit
    build["implementation_committed_at"] = now_iso()
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_accept(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    accepted_at = optional(args.accepted_at) or now_iso()
    build["pm_accepted_at"] = accepted_at
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_complete(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    commit = optional(args.implementation_commit)
    if not commit:
        raise SystemExit("必须提供 implementation_commit")
    accepted_at = optional(args.accepted_at) or now_iso()
    build["implementation_commit"] = commit
    build["implementation_committed_at"] = now_iso()
    build["pm_accepted_at"] = accepted_at
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_validate_close(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)

    mode = build.get("mode")
    executor = build.get("executor")
    validate_mode_executor(mode, executor)

    if not build.get("anchor"):
        raise SystemExit("build 合同缺少 anchor，不能收尾。")
    if not build.get("implementation_commit"):
        raise SystemExit("build 合同缺少 implementation_commit：实现提交尚未记录，不能收尾。")
    if not build.get("pm_accepted_at"):
        raise SystemExit("build 合同缺少 pm_accepted_at：PM 验收未记录，不能收尾。")
    if mode == "worktree" and not build.get("branch"):
        raise SystemExit("build 合同要求隔离环境，但缺少 branch。")
    if mode == "main" and build.get("branch") not in (None, "", "main", "master"):
        raise SystemExit("build 合同是 main 模式，但 branch 不是 main/master，不能按主线直收。")

    print(json.dumps(build, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    start = sub.add_parser("start", help="record PM build choices before implementation")
    start.add_argument("module_dir")
    start.add_argument("--anchor", required=True)
    start.add_argument("--mode", required=True, choices=sorted(VALID_MODES))
    start.add_argument("--executor", required=True, choices=sorted(VALID_EXECUTORS))
    start.add_argument("--branch")
    start.add_argument("--worktree")
    start.add_argument("--baseline-sha")
    start.add_argument("--audit-dir")
    start.set_defaults(func=cmd_start)

    commit = sub.add_parser("commit", help="record the implementation commit produced by build")
    commit.add_argument("module_dir")
    commit.add_argument("--implementation-commit", required=True)
    commit.set_defaults(func=cmd_commit)

    accept = sub.add_parser("accept", help="record PM acceptance before build-close")
    accept.add_argument("module_dir")
    accept.add_argument("--accepted-at")
    accept.set_defaults(func=cmd_accept)

    complete = sub.add_parser("complete", help="record implementation commit and PM acceptance atomically")
    complete.add_argument("module_dir")
    complete.add_argument("--implementation-commit", required=True)
    complete.add_argument("--accepted-at")
    complete.set_defaults(func=cmd_complete)

    validate = sub.add_parser("validate-close", help="validate that build-close may proceed")
    validate.add_argument("module_dir")
    validate.set_defaults(func=cmd_validate_close)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        args.func(args)
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
