#!/usr/bin/env python3
"""Create contract-bound coverage evidence from checks-spec and captured pages."""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def read_json(path: Path, label: str) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"{label} 不存在：{path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{label} 不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"{label} 顶层必须是对象。")
    return value


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    temporary.replace(path)


def load_checks_diff():
    script = Path(__file__).with_name("checks-diff.py")
    spec = importlib.util.spec_from_file_location("pmai_checks_diff_coverage", script)
    if spec is None or spec.loader is None:
        raise SystemExit("无法加载 checks-diff.py。")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def run(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).expanduser().resolve()
    module_dir = Path(args.module_dir).expanduser()
    module_dir = (
        module_dir.resolve()
        if module_dir.is_absolute()
        else (repo_root / module_dir).resolve()
    )
    plan_path = Path(args.plan).expanduser()
    plan_path = plan_path.resolve() if plan_path.is_absolute() else repo_root / plan_path
    artifacts_root = Path(args.artifacts).expanduser()
    artifacts_root = (
        artifacts_root.resolve()
        if artifacts_root.is_absolute()
        else repo_root / artifacts_root
    )
    output = Path(args.output).expanduser()
    output = output.resolve() if output.is_absolute() else repo_root / output

    meta = read_json(module_dir / ".work-meta.json", "build contract")
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit("build contract 缺少 build 对象。")
    commit = str(build.get("implementation_commit") or "").strip()
    source_hash = str(build.get("approved_source_hash") or "").strip()
    finalization = build.get("finalization")
    if not commit or not source_hash:
        raise SystemExit("coverage evidence 缺少 implementation_commit/source_hash。")
    if (
        not isinstance(finalization, dict)
        or not finalization.get("requested_at")
        or finalization.get("requested_commit") != commit
    ):
        raise SystemExit("coverage evidence 只能用于当前 PM 定稿候选。")

    plan = read_json(plan_path, "checks-spec")
    checks = plan.get("checks")
    if not isinstance(checks, list) or not checks:
        raise SystemExit("checks-spec.checks 必须是非空数组。")
    checks_diff = load_checks_diff()
    issues = checks_diff.build(plan_path, artifacts_root)
    issue_rows = [
        {
            "severity": issue.severity,
            "check_id": issue.check_id,
            "title": issue.title,
            "detail": issue.detail,
        }
        for issue in issues
    ]
    confirmed_states = set(args.confirm_state)
    known_ids = {str(check.get("id") or "") for check in checks if isinstance(check, dict)}
    unknown = sorted(confirmed_states - known_ids)
    if unknown:
        raise SystemExit("--confirm-state 没有对应 checks-spec 项：" + "、".join(unknown))

    items = []
    for check in checks:
        if not isinstance(check, dict):
            raise SystemExit("checks-spec.checks 只能包含对象。")
        check_id = str(check.get("id") or "").strip()
        check_issues = [row for row in issue_rows if row["check_id"] == check_id]
        blocking = [row for row in check_issues if row["severity"] in {"P0", "P1"}]
        states = check.get("must_cover_states") or []
        if not isinstance(states, list):
            raise SystemExit(f"checks-spec {check_id}.must_cover_states 必须是数组。")
        state_confirmed = not states or check_id in confirmed_states
        status = "pass" if not blocking and state_confirmed else "needs-review"
        items.append(
            {
                "id": check_id,
                "status": status,
                "machine_issues": blocking,
                "declared_states": [str(value) for value in states],
                "states_confirmed": state_confirmed,
            }
        )

    passed = all(item["status"] == "pass" for item in items)
    artifact = {
        "schema_version": 1,
        "check": "coverage",
        "status": "pass" if passed else "needs-review",
        "implementation_commit": commit,
        "source_hash": source_hash,
        "plan": str(plan_path),
        "artifacts": str(artifacts_root),
        "checked_at": now_iso(),
        "items": items,
        "issues": issue_rows,
        "semantic_confirmation": {
            "confirmed_state_checks": sorted(confirmed_states),
        },
    }
    write_json(output, artifact)
    print(json.dumps(artifact, ensure_ascii=False))
    return 0 if passed else 1


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo-root", default=".")
    result.add_argument("--module-dir", required=True)
    result.add_argument("--plan", required=True)
    result.add_argument("--artifacts", required=True)
    result.add_argument("--output", required=True)
    result.add_argument("--confirm-state", action="append", default=[])
    return result


def main(argv: list[str] | None = None) -> int:
    try:
        return run(parser().parse_args(argv))
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise


if __name__ == "__main__":
    raise SystemExit(main())
