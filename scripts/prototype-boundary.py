#!/usr/bin/env python3
"""Audit one prototype candidate for implementation-depth boundary drift."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

from _lib.delivery_policy import delivery_policy_hash, validate_delivery_policy


PATH_SIGNAL_RULES = (
    (
        "database-migration",
        re.compile(
            r"(^|/)(migrations?|prisma/migrations)(/|$)|"
            r"(^|/)schema\.prisma$|(^|/)(db|database)/[^/]+\.sql$",
            re.IGNORECASE,
        ),
        "新增或修改数据库 schema / migration",
    ),
    (
        "production-infrastructure",
        re.compile(
            r"(^|/)(terraform|k8s|kubernetes|helm)(/|$)|\.tf$|"
            r"(^|/)(Dockerfile|docker-compose[^/]*)$|"
            r"(^|/)\.github/workflows/[^/]*(deploy|release)[^/]*$",
            re.IGNORECASE,
        ),
        "新增或修改生产基础设施与部署编排",
    ),
    (
        "secret-config",
        re.compile(r"(^|/)\.env($|\.(?!example$|sample$))", re.IGNORECASE),
        "新增或修改真实环境与密钥配置",
    ),
)

CONTENT_SIGNAL_RULES = (
    (
        "database-runtime",
        re.compile(
            r"DATABASE_URL|new\s+PrismaClient|mongoose\.connect|"
            r"mysql\.(createConnection|createPool)|new\s+Pool\s*\(|"
            r"[@\"'](?:prisma|typeorm|sequelize|mongoose|supabase)",
            re.IGNORECASE,
        ),
        "接入真实数据库 runtime",
    ),
    (
        "production-auth",
        re.compile(
            r"next-auth|@auth/|auth0|clerk|passport|oidc-client|"
            r"createClient\s*\([^\n]*supabase",
            re.IGNORECASE,
        ),
        "接入真实鉴权或生产账号体系",
    ),
    (
        "external-side-effect",
        re.compile(
            r"fetch\s*\(\s*['\"]https?://|"
            r"axios\.(post|put|patch|delete)\s*\(\s*['\"]https?://|"
            r"webhook[_-]?url",
            re.IGNORECASE,
        ),
        "接入可能产生真实外部副作用的调用",
    ),
)

MOCK_SEGMENTS = {"demo", "demos", "fake", "fakes", "fixture", "fixtures", "mock", "mocks", "stub", "stubs"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def git(repo_root: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or f"git {' '.join(args)} 执行失败。")
    return result.stdout


def normalize_path(value: str) -> str:
    text = value.strip().replace("\\", "/")
    while text.startswith("./"):
        text = text[2:]
    return PurePosixPath(text).as_posix().rstrip("/")


def path_within(path: str, parent: str) -> bool:
    return path == parent or path.startswith(parent.rstrip("/") + "/")


def is_mock_support_path(path: str) -> bool:
    return any(part.lower() in MOCK_SEGMENTS for part in PurePosixPath(path).parts)


def added_lines(repo_root: Path, base: str, head: str, path: str) -> str:
    diff = git(repo_root, "diff", "--unified=0", base, head, "--", path)
    return "\n".join(
        line[1:]
        for line in diff.splitlines()
        if line.startswith("+") and not line.startswith("+++")
    )


def parse_approvals(values: list[str]) -> dict[str, str]:
    approvals: dict[str, str] = {}
    for value in values:
        category, separator, reference = value.partition("=")
        category = category.strip()
        reference = reference.strip()
        if not separator or not category or not reference:
            raise SystemExit("--approved-real-edge 必须写成 <category>=<decision reference>。")
        approvals[category] = reference
    return approvals


def detect_signals(repo_root: Path, base: str, head: str, paths: list[str]) -> list[dict[str, str]]:
    signals: list[dict[str, str]] = []
    seen: set[tuple[str, str, str]] = set()
    for path in paths:
        for category, pattern, reason in PATH_SIGNAL_RULES:
            if pattern.search(path):
                key = (category, path, reason)
                if key not in seen:
                    seen.add(key)
                    signals.append({"category": category, "path": path, "reason": reason})
        if is_mock_support_path(path):
            continue
        content = added_lines(repo_root, base, head, path)
        for category, pattern, reason in CONTENT_SIGNAL_RULES:
            if pattern.search(content):
                key = (category, path, reason)
                if key not in seen:
                    seen.add(key)
                    signals.append({"category": category, "path": path, "reason": reason})
    return signals


def load_build(module_dir: Path) -> dict[str, Any]:
    meta_path = module_dir / ".work-meta.json"
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"缺少 build 合同：{meta_path}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"build 合同不是合法 JSON：{meta_path}") from exc
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit("缺少 build 合同。")
    if int(build.get("contract_version", 1)) < 3:
        raise SystemExit("prototype-boundary 只适用于带实现深度合同的 build contract v3+。")
    target = build.get("target")
    if not isinstance(target, dict) or target.get("kind") != "prototype":
        raise SystemExit("prototype-boundary 只检查 target.kind=prototype 的构建。")
    try:
        policy = validate_delivery_policy(build.get("delivery_policy"), "prototype")
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    if build.get("delivery_policy_hash") != delivery_policy_hash(policy):
        raise SystemExit("build.delivery_policy_hash 与实现深度合同不一致。")
    return build


def build_report(args: argparse.Namespace) -> dict[str, Any]:
    module_dir = Path(args.module_dir).expanduser().resolve()
    repo_root = Path(git(module_dir, "rev-parse", "--show-toplevel").strip()).resolve()
    build = load_build(module_dir)
    base = str(build.get("baseline_sha") or "").strip()
    head = str(build.get("implementation_commit") or "").strip()
    if not base or not head:
        raise SystemExit("build 合同缺少 baseline_sha 或 implementation_commit。")

    changed_paths = [
        normalize_path(path)
        for path in git(repo_root, "diff", "--name-only", "--no-renames", base, head).splitlines()
        if normalize_path(path)
    ]
    target_paths = [normalize_path(str(path)) for path in build["target"].get("paths", [])]
    module_rel = module_dir.relative_to(repo_root).as_posix()
    framework_managed = {f"{module_rel}/.work-meta.json"}
    audit_root = str(build.get("audit_dir") or f".pm-workflow/audits/{module_dir.name}")
    outside_target_paths = [
        path
        for path in changed_paths
        if path not in framework_managed
        and not path_within(path, audit_root)
        and not any(path_within(path, target) for target in target_paths)
    ]
    target_changed_paths = [
        path for path in changed_paths if any(path_within(path, target) for target in target_paths)
    ]
    detected_signals = detect_signals(repo_root, base, head, target_changed_paths)
    approvals = parse_approvals(args.approved_real_edge)
    approved_real_edges: list[dict[str, Any]] = []
    unapproved_signals: list[dict[str, str]] = []
    for signal in detected_signals:
        reference = approvals.get(signal["category"])
        if reference:
            approved_real_edges.append({**signal, "decision_reference": reference})
        else:
            unapproved_signals.append(signal)
    unused_approvals = sorted(set(approvals) - {item["category"] for item in detected_signals})
    if unused_approvals:
        raise SystemExit("--approved-real-edge 没有对应检测信号：" + "、".join(unused_approvals))

    if outside_target_paths or unapproved_signals:
        status = "blocked"
    elif not args.confirm_no_real_system_changes:
        status = "needs-review"
    else:
        status = "pass"
    return {
        "schema_version": 1,
        "check": "prototype-boundary",
        "status": status,
        "target_kind": "prototype",
        "implementation_mode": "interactive-simulation",
        "policy_hash": build["delivery_policy_hash"],
        "source_hash": build.get("approved_source_hash"),
        "baseline_sha": base,
        "implementation_commit": head,
        "target_paths": target_paths,
        "changed_paths": changed_paths,
        "outside_target_paths": outside_target_paths,
        "detected_signals": detected_signals,
        "unapproved_signals": unapproved_signals,
        "approved_real_edges": approved_real_edges,
        "simulated_capabilities": list(dict.fromkeys(args.simulated_capability)),
        "semantic_review": {
            "confirmed_no_real_system_changes": bool(args.confirm_no_real_system_changes),
            "reviewed_at": now_iso(),
        },
    }


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("module_dir")
    result.add_argument("--output", required=True)
    result.add_argument("--confirm-no-real-system-changes", action="store_true")
    result.add_argument("--simulated-capability", action="append", default=[])
    result.add_argument("--approved-real-edge", action="append", default=[])
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        report = build_report(args)
        module_dir = Path(args.module_dir).expanduser().resolve()
        repo_root = Path(git(module_dir, "rev-parse", "--show-toplevel").strip()).resolve()
        output = Path(args.output).expanduser()
        output = output if output.is_absolute() else repo_root / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, ensure_ascii=False))
        return 0 if report["status"] == "pass" else 1
    except (OSError, ValueError) as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
