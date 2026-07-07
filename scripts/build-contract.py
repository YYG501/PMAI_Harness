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
import subprocess


VALID_MODES = {"worktree", "main"}
VALID_EXECUTORS = {"claude-code", "codex", "cursor-agent", "gemini", "opencode", "manual"}
AUDIT_FILES = {
    "browser_smoke": "browser-smoke.json",
    "coverage": "coverage.json",
    "visual": "visual.json",
    "behavior": "behavior.json",
}
BROWSER_SMOKE_ALLOWED_STATUSES = {"pass", "limited", "skipped", "fail", "blocked"}
BROWSER_SMOKE_LIMITED_STATUSES = {"limited", "skipped", "fail", "blocked"}
VISUAL_LIMITED_STATUSES = {"limited", "skipped", "blocked", "not-run"}
VISUAL_ALLOWED_STATUSES = {"pass", "needs-review", *VISUAL_LIMITED_STATUSES}
BEHAVIOR_ALLOWED_STATUSES = {"pass", "fail", "skipped", "limited", "blocked"}
BEHAVIOR_LIMITED_STATUSES = {"skipped", "limited", "blocked"}


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


def parse_builder_json(value: str | None) -> dict:
    raw = optional(value)
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"builder 必须是合法 JSON 对象: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit("builder 必须是 JSON 对象")
    return data


def validate_builder(builder: dict) -> None:
    for key in ("model", "thinking"):
        value = builder.get(key)
        if value is not None and not isinstance(value, str):
            raise SystemExit(f"builder.{key} 必须是字符串")
    overrides = builder.get("overrides")
    if overrides is not None and not isinstance(overrides, dict):
        raise SystemExit("builder.overrides 必须是对象")


def build_snapshot(args: argparse.Namespace) -> dict:
    builder = parse_builder_json(args.builder_json)
    model = optional(args.builder_model)
    thinking = optional(args.builder_thinking)
    if model:
        builder["model"] = model
    if thinking:
        builder["thinking"] = thinking
    validate_builder(builder)
    return builder


def repo_root_for(module_dir: Path) -> Path:
    resolved = module_dir.expanduser().resolve()
    try:
        top = subprocess.check_output(
            ["git", "-C", str(resolved), "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if top:
            return Path(top)
    except Exception:
        pass

    for parent in [resolved, *resolved.parents]:
        if (parent / ".pm-workflow").is_dir():
            return parent

    # Expected module shape: <repo>/docs/modules/<module>
    if resolved.parent.name == "modules" and resolved.parent.parent.name == "docs":
        return resolved.parent.parent.parent
    return resolved.parent


def resolve_repo_path(repo_root: Path, value: str | None, field_name: str) -> Path:
    raw = optional(value)
    if not raw:
        raise SystemExit(f"build 合同缺少 {field_name}，不能收尾。")
    path = Path(raw).expanduser()
    return path if path.is_absolute() else repo_root / path


def load_audit_json(path: Path, label: str) -> dict:
    if not path.exists():
        raise SystemExit(f"build 验收证据不完整：缺少 {label} 结果 {path}，不能收尾。")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{label} 结果不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"{label} 结果顶层必须是 JSON 对象：{path}")
    return data


def require_object_list(data: dict, key: str, label: str) -> list[dict]:
    value = data.get(key)
    if not isinstance(value, list) or any(not isinstance(item, dict) for item in value):
        raise SystemExit(f"{label} 结果字段 {key} 必须是对象数组。")
    return value


def audit_exception(build: dict) -> dict | None:
    value = build.get("audit_exception")
    return value if isinstance(value, dict) else None


def has_audit_exception(build: dict) -> bool:
    exc = audit_exception(build)
    return bool(exc and exc.get("accepted_at") and exc.get("reason"))


def validate_audit_evidence(module_dir: Path, build: dict) -> None:
    repo_root = repo_root_for(module_dir)
    audit_dir = resolve_repo_path(repo_root, build.get("audit_dir"), "audit_dir")
    browser_smoke = load_audit_json(
        audit_dir / AUDIT_FILES["browser_smoke"], "浏览器主动 smoke"
    )
    coverage = load_audit_json(audit_dir / AUDIT_FILES["coverage"], "覆盖审计")
    visual = load_audit_json(audit_dir / AUDIT_FILES["visual"], "视觉门")
    behavior = load_audit_json(audit_dir / AUDIT_FILES["behavior"], "行为审")
    synthesis = audit_dir / "synthesis.md"
    if not synthesis.exists():
        raise SystemExit(f"build 验收证据不完整：缺少合成报告 {synthesis}，不能收尾。")

    require_object_list(coverage, "items", "覆盖审计")
    visual_findings = require_object_list(visual, "findings", "视觉门")

    browser_smoke_status = str(browser_smoke.get("status", ""))
    if browser_smoke_status not in BROWSER_SMOKE_ALLOWED_STATUSES:
        raise SystemExit(
            f"浏览器主动 smoke status 不合法：{browser_smoke_status}"
            f"（允许 {', '.join(sorted(BROWSER_SMOKE_ALLOWED_STATUSES))}）。"
        )
    if browser_smoke_status == "pass" and browser_smoke.get("active_browser_smoke") is not True:
        raise SystemExit("浏览器主动 smoke 证据不是 active browser smoke，不能当作 browser 验收前提。")

    visual_status = str(
        visual.get("status")
        or ("pass" if not visual_findings else "needs-review")
    )
    if visual_status not in VISUAL_ALLOWED_STATUSES:
        raise SystemExit(
            f"视觉门 status 不合法：{visual_status}（允许 {', '.join(sorted(VISUAL_ALLOWED_STATUSES))}）。"
        )

    behavior_status = str(behavior.get("status", ""))
    if behavior_status not in BEHAVIOR_ALLOWED_STATUSES:
        raise SystemExit(
            f"行为审 status 不合法：{behavior_status}（允许 {', '.join(sorted(BEHAVIOR_ALLOWED_STATUSES))}）。"
        )
    if behavior_status == "fail":
        raise SystemExit("行为审未通过：不能收尾。请先修到通过，或重新跑 build 验收。")
    if browser_smoke_status in BROWSER_SMOKE_LIMITED_STATUSES:
        if visual_status not in VISUAL_LIMITED_STATUSES:
            raise SystemExit(
                "浏览器主动 smoke 未通过：视觉门不能写 pass/needs-review。"
                "请改为 limited/skipped/blocked，并记录 PM 明确接受的风险。"
            )
        if behavior_status not in BEHAVIOR_LIMITED_STATUSES:
            raise SystemExit(
                "浏览器主动 smoke 未通过：行为审不能写 pass。"
                "请改为 limited/skipped/blocked，并记录 PM 明确接受的风险。"
            )

    limited = []
    if browser_smoke_status in BROWSER_SMOKE_LIMITED_STATUSES:
        limited.append("浏览器主动 smoke")
    if visual_status in VISUAL_LIMITED_STATUSES:
        limited.append("视觉门")
    if behavior_status in BEHAVIOR_LIMITED_STATUSES:
        limited.append("行为审")
    if limited and not has_audit_exception(build):
        raise SystemExit(
            "build 验收存在受限/跳过/失败/阻塞项："
            + "、".join(limited)
            + "。必须记录 PM 明确接受该缺口后才能收尾。"
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

    builder = build_snapshot(args)
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
    builder_profile = optional(args.builder_profile)
    if builder_profile:
        build["builder_profile"] = builder_profile
    if builder:
        build["builder"] = builder

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


def cmd_audit_exception(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    reason = optional(args.reason)
    if not reason:
        raise SystemExit("必须提供 PM 接受三道审受限/跳过的原因")
    build["audit_exception"] = {
        "accepted_at": optional(args.accepted_at) or now_iso(),
        "reason": reason,
    }
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
    builder = build.get("builder")
    if builder is not None:
        if not isinstance(builder, dict):
            raise SystemExit("build 合同里的 builder 必须是对象。")
        validate_builder(builder)
    validate_audit_evidence(module_dir, build)

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
    start.add_argument("--builder-profile")
    start.add_argument("--builder-json")
    start.add_argument("--builder-model")
    start.add_argument("--builder-thinking")
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

    audit_exception = sub.add_parser(
        "audit-exception",
        help="record PM acceptance for limited/skipped visual or browser audit evidence",
    )
    audit_exception.add_argument("module_dir")
    audit_exception.add_argument("--reason", required=True)
    audit_exception.add_argument("--accepted-at")
    audit_exception.set_defaults(func=cmd_audit_exception)

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
