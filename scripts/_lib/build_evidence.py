"""Evidence validation for Build contracts, independent from CLI transitions."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from .build_schema import canonical_final_checks, contract_version, optional


PASSING_EVIDENCE_STATUSES = {"pass", "passed", "clean", "built"}
LIMITED_EVIDENCE_STATUSES = {"limited", "skipped", "blocked", "needs-review"}
VALID_EVIDENCE_STATUSES = {
    *PASSING_EVIDENCE_STATUSES,
    *LIMITED_EVIDENCE_STATUSES,
    "fail",
}
EVIDENCE_LABELS = {
    "current-page": "当前页面走查",
    "tests": "测试",
    "typecheck": "类型检查",
    "build": "生产构建",
    "browser-smoke": "浏览器主动 smoke",
    "browser-acceptance": "浏览器批量验收",
    "prototype-boundary": "原型实现边界",
    "coverage": "覆盖审计",
    "visual": "视觉门",
    "behavior": "行为审",
}
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


def repo_root_for(module_dir: Path) -> Path:
    resolved = module_dir.expanduser().resolve()
    result = subprocess.run(
        ["git", "-C", str(resolved), "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip():
        return Path(result.stdout.strip())
    for parent in [resolved, *resolved.parents]:
        if (parent / ".pm-workflow").is_dir():
            return parent
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
    exception = audit_exception(build)
    return bool(exception and exception.get("accepted_at") and exception.get("reason"))


def evidence_exception_for(build: dict, check_name: str) -> bool:
    exception = audit_exception(build)
    if not exception or not exception.get("accepted_at") or not exception.get("reason"):
        return False
    checks = exception.get("checks")
    if checks is None:
        return True
    return isinstance(checks, list) and check_name in checks


def validate_legacy_audit(module_dir: Path, build: dict) -> None:
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
    browser_status = str(browser_smoke.get("status", ""))
    if browser_status not in BROWSER_SMOKE_ALLOWED_STATUSES:
        raise SystemExit(
            f"浏览器主动 smoke status 不合法：{browser_status}"
            f"（允许 {', '.join(sorted(BROWSER_SMOKE_ALLOWED_STATUSES))}）。"
        )
    if browser_status == "pass" and browser_smoke.get("active_browser_smoke") is not True:
        raise SystemExit("浏览器主动 smoke 证据不是 active browser smoke，不能当作 browser 验收前提。")
    visual_status = str(visual.get("status") or ("pass" if not visual_findings else "needs-review"))
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
    if browser_status in BROWSER_SMOKE_LIMITED_STATUSES:
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
    if browser_status in BROWSER_SMOKE_LIMITED_STATUSES:
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


def validate_prototype_boundary_artifact(build: dict, artifact: dict) -> None:
    required_values = {
        "schema_version": 1,
        "check": "prototype-boundary",
        "status": "pass",
        "target_kind": "prototype",
        "implementation_mode": "interactive-simulation",
        "policy_hash": build.get("delivery_policy_hash"),
        "source_hash": build.get("approved_source_hash"),
        "baseline_sha": build.get("baseline_sha"),
        "implementation_commit": build.get("implementation_commit"),
        "target_paths": build.get("target", {}).get("paths"),
    }
    for key, expected in required_values.items():
        if artifact.get(key) != expected:
            raise SystemExit(f"原型实现边界证据字段不一致：{key}。")
    for key in (
        "changed_paths",
        "outside_target_paths",
        "detected_signals",
        "unapproved_signals",
        "approved_real_edges",
        "simulated_capabilities",
    ):
        if not isinstance(artifact.get(key), list):
            raise SystemExit(f"原型实现边界证据 {key} 必须是数组。")
    if artifact["outside_target_paths"]:
        raise SystemExit("原型实现边界发现批准范围外改动，不能定稿。")
    if artifact["unapproved_signals"]:
        raise SystemExit("原型实现边界发现未经决定允许的真实系统建设信号，不能定稿。")
    semantic_review = artifact.get("semantic_review")
    if not isinstance(semantic_review, dict) or semantic_review.get(
        "confirmed_no_real_system_changes"
    ) is not True:
        raise SystemExit("原型实现边界尚未完成语义复核，不能定稿。")
    if not semantic_review.get("reviewed_at"):
        raise SystemExit("原型实现边界语义复核缺少 reviewed_at。")
    for edge in artifact["approved_real_edges"]:
        if not isinstance(edge, dict) or not str(edge.get("decision_reference") or "").strip():
            raise SystemExit("原型真实边缘能力缺少 active decision reference。")


def validate_fresh_evidence(module_dir: Path, build: dict) -> None:
    acceptance = build.get("acceptance")
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    required = canonical_final_checks({"build": build})
    evidence = acceptance.get("evidence", [])
    if not isinstance(evidence, list) or any(not isinstance(item, dict) for item in evidence):
        raise SystemExit("build.acceptance.evidence 必须是对象数组。")
    approved_hash = str(build.get("approved_source_hash", ""))
    implementation_commit = str(build.get("implementation_commit", ""))
    by_name: dict[str, dict] = {}
    duplicates: set[str] = set()
    for item in evidence:
        name = str(item.get("name", "")).strip()
        if not name:
            raise SystemExit("build 验收证据缺少 name。")
        if name in by_name:
            duplicates.add(name)
        by_name[name] = item
    if duplicates:
        raise SystemExit("build 验收证据包含重复检查：" + "、".join(sorted(duplicates)))
    missing = [name for name in required if name not in by_name]
    if missing:
        raise SystemExit("build 验收证据不完整：缺少 " + "、".join(missing) + "。")
    repo_root = repo_root_for(module_dir)
    resolved_artifacts: dict[str, dict] = {}
    for name in required:
        item = by_name[name]
        label = EVIDENCE_LABELS.get(name, name)
        status = str(item.get("status", "")).strip()
        if str(item.get("source_hash", "")) != approved_hash:
            raise SystemExit(
                f"验收证据 {name} 已过期：source_hash 与当前 approved_source_hash 不一致。"
            )
        if str(item.get("commit", "")) != implementation_commit:
            raise SystemExit(
                f"验收证据 {name} 已过期：commit 与当前 implementation_commit 不一致。"
            )
        if not item.get("checked_at"):
            raise SystemExit(f"验收证据 {name} 缺少 checked_at。")
        if name in {"browser-smoke", "browser-acceptance"} and status not in PASSING_EVIDENCE_STATUSES:
            raise SystemExit(
                f"UI 验收缺少可用的主动浏览器能力：{name} 必须通过，"
                "v2 不能用 exception 跳过。请启用 gstack/browse、browser 或 Playwright 后重跑。"
            )
        if status in PASSING_EVIDENCE_STATUSES:
            pass
        elif status in LIMITED_EVIDENCE_STATUSES:
            if not evidence_exception_for(build, name):
                raise SystemExit(
                    f"build 验收存在受限/跳过/失败/阻塞项：{label}。"
                    "必须记录 PM 明确接受该缺口后才能落地主线。"
                )
        elif name == "behavior" and status == "fail":
            raise SystemExit("行为审未通过：不能落地主线。请先修到通过。")
        else:
            raise SystemExit(f"验收证据 {name} 未通过：status={status or '<empty>'}。")
        artifact_value = item.get("artifact")
        artifact = optional(artifact_value) if isinstance(artifact_value, str) else None
        if artifact:
            path = Path(artifact).expanduser()
            path = path if path.is_absolute() else repo_root / path
            if not path.exists():
                raise SystemExit(f"验收证据 {label} 的 artifact 不存在：{path}")
            if path.suffix == ".json":
                resolved_artifacts[name] = load_audit_json(path, name)
    browser = by_name.get("browser-smoke")
    visual = by_name.get("visual")
    behavior = by_name.get("behavior")
    if browser:
        browser_status = str(browser.get("status", ""))
        artifact = resolved_artifacts.get("browser-smoke", {})
        if browser_status in PASSING_EVIDENCE_STATUSES and artifact.get("active_browser_smoke") is not True:
            raise SystemExit("浏览器主动 smoke 证据不是 active browser smoke，不能当作验收前提。")
        if browser_status in LIMITED_EVIDENCE_STATUSES:
            if visual and str(visual.get("status", "")) in PASSING_EVIDENCE_STATUSES:
                raise SystemExit("浏览器主动 smoke 未通过：视觉门不能写 pass。")
            if behavior and str(behavior.get("status", "")) in PASSING_EVIDENCE_STATUSES:
                raise SystemExit("浏览器主动 smoke 未通过：行为审不能写 pass。")
    if behavior and str(behavior.get("status", "")) == "fail":
        raise SystemExit("行为审未通过：不能落地主线。请先修到通过。")
    batched_browser = by_name.get("browser-acceptance")
    if batched_browser:
        artifact = resolved_artifacts.get("browser-acceptance")
        if artifact is None:
            raise SystemExit("浏览器批量验收缺少 JSON artifact。")
        expected = {
            "schema_version": 1,
            "check": "browser-acceptance",
            "status": "pass",
            "implementation_commit": implementation_commit,
            "source_hash": approved_hash,
            "active_browser_smoke": True,
            "single_chain_invocation": True,
        }
        for key, value in expected.items():
            if artifact.get(key) != value:
                raise SystemExit(f"浏览器批量验收 artifact 字段不一致：{key}。")
        if set(artifact.get("covers", [])) != {"smoke", "visual", "behavior"}:
            raise SystemExit("浏览器批量验收没有同时覆盖 smoke、visual 和 behavior。")
        flows = artifact.get("flows")
        if (
            not isinstance(flows, list)
            or not flows
            or any(not isinstance(flow, dict) or flow.get("status") != "pass" for flow in flows)
        ):
            raise SystemExit("浏览器批量验收存在未通过的受影响流程。")
    if contract_version(build) >= 3 and build.get("target", {}).get("kind") == "prototype":
        artifact = resolved_artifacts.get("prototype-boundary")
        if artifact is None:
            raise SystemExit("原型实现边界缺少 JSON artifact，不能形成验收就绪快照。")
        validate_prototype_boundary_artifact(build, artifact)
