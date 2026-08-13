"""Evidence validation for Build contracts, independent from CLI transitions."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from .browser_evidence import LEGACY_BROWSER_CHECK_COVERAGE, browser_batch_digest
from .build_schema import canonical_final_checks, contract_version, optional
from .candidate_binding import validate_candidate_binding
from .final_validation import LIMITABLE_CHECKS, exception_allows


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
    binding = build.get("candidate_binding") if isinstance(build.get("candidate_binding"), dict) else {}
    required_values = {
        "schema_version": 1,
        "check": "prototype-boundary",
        "status": "pass",
        "target_kind": "prototype",
        "implementation_mode": "interactive-simulation",
        "policy_hash": build.get("delivery_policy_hash"),
        "source_hash": build.get("approved_source_hash"),
        "baseline_sha": binding.get("base_commit", build.get("baseline_sha")),
        "implementation_commit": build.get("implementation_commit"),
        "target_paths": build.get("target", {}).get("paths"),
    }
    if binding:
        required_values["candidate_tree_digest"] = binding.get("target_tree_digest")
        required_values["candidate_diff_mode"] = binding.get("diff_mode")
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


def validate_structured_coverage_artifact(
    artifact: dict, implementation_commit: str, approved_hash: str
) -> None:
    expected = {
        "schema_version": 1,
        "check": "coverage",
        "status": "pass",
        "implementation_commit": implementation_commit,
        "source_hash": approved_hash,
    }
    for key, value in expected.items():
        if artifact.get(key) != value:
            raise SystemExit(f"结构化 coverage artifact 字段不一致：{key}。")
    items = require_object_list(artifact, "items", "结构化 coverage")
    issues = require_object_list(artifact, "issues", "结构化 coverage")
    if not items:
        raise SystemExit("结构化 coverage artifact 的 items 不能为空。")
    if any(item.get("status") != "pass" for item in items):
        raise SystemExit("结构化 coverage artifact 存在未通过的检查项。")
    if any(item.get("states_confirmed") is not True for item in items):
        raise SystemExit("结构化 coverage artifact 存在未确认的 must_cover_states。")
    if any(str(issue.get("severity") or "").upper() in {"P0", "P1"} for issue in issues):
        raise SystemExit("结构化 coverage artifact 仍有 P0/P1 覆盖缺口。")
    for item in items:
        machine_issues = item.get("machine_issues")
        if not isinstance(machine_issues, list) or any(
            not isinstance(issue, dict) for issue in machine_issues
        ):
            raise SystemExit("结构化 coverage item.machine_issues 必须是对象数组。")
        if any(
            str(issue.get("severity") or "").upper() in {"P0", "P1"}
            for issue in machine_issues
        ):
            raise SystemExit("结构化 coverage item 仍有 P0/P1 覆盖缺口。")


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
    if build.get("candidate_binding") is not None:
        try:
            validate_candidate_binding(repo_root, build)
        except ValueError as exc:
            raise SystemExit(str(exc)) from exc
    resolved_artifacts: dict[str, dict] = {}
    resolved_artifact_paths: dict[str, Path] = {}
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
            bound_exception = False
            if name in LIMITABLE_CHECKS:
                artifact_value = item.get("artifact")
                if isinstance(artifact_value, str) and artifact_value.strip():
                    bound_path = Path(artifact_value).expanduser()
                    bound_path = (
                        bound_path if bound_path.is_absolute() else repo_root / bound_path
                    )
                    if bound_path.suffix == ".json" and bound_path.is_file():
                        bound_exception = exception_allows(
                            build, name, load_audit_json(bound_path, name)
                        )
            else:
                bound_exception = evidence_exception_for(build, name)
            if not bound_exception:
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
                resolved_artifact_paths[name] = path.resolve()
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
    coverage_artifact = resolved_artifacts.get("coverage")
    if isinstance(coverage_artifact, dict) and coverage_artifact.get("check") == "coverage":
        validate_structured_coverage_artifact(
            coverage_artifact, implementation_commit, approved_hash
        )
    expected_legacy_checks = set(required) & set(LEGACY_BROWSER_CHECK_COVERAGE)
    legacy_derived = {
        name: resolved_artifacts[name]
        for name in expected_legacy_checks
        if isinstance(resolved_artifacts.get(name), dict)
        and resolved_artifacts[name].get("derived_from")
    }
    if legacy_derived:
        if set(legacy_derived) != expected_legacy_checks:
            raise SystemExit("legacy browser adapter 的派生证据未精确覆盖合同要求。")
        source_names = {str(item.get("derived_from")) for item in legacy_derived.values()}
        digests = {str(item.get("browser_batch_digest")) for item in legacy_derived.values()}
        if len(source_names) != 1 or len(digests) != 1:
            raise SystemExit("legacy browser adapter 没有绑定同一批次摘要。")
        source_name = next(iter(source_names))
        if not source_name or Path(source_name).name != source_name or source_name in {".", ".."}:
            raise SystemExit("legacy browser adapter 的 derived_from 必须是安全文件名。")
        parents = {resolved_artifact_paths[name].parent for name in legacy_derived}
        if len(parents) != 1:
            raise SystemExit("legacy browser adapter 的派生证据必须位于同一 audit 目录。")
        batch_path = next(iter(parents)) / source_name
        batch = load_audit_json(batch_path, "legacy browser batch")
        expected_batch = {
            "schema_version": 1,
            "check": "browser-acceptance",
            "status": "pass",
            "implementation_commit": implementation_commit,
            "source_hash": approved_hash,
            "active_browser_smoke": True,
            "single_chain_invocation": True,
        }
        for key, value in expected_batch.items():
            if batch.get(key) != value:
                raise SystemExit(f"legacy browser batch 字段不一致：{key}。")
        adapter = batch.get("legacy_adapter")
        if not isinstance(adapter, dict) or set(adapter.get("checks", [])) != expected_legacy_checks:
            raise SystemExit("legacy browser batch 映射的检查与当前合同不一致。")
        actual_digest = browser_batch_digest(batch)
        if batch.get("batch_digest") != actual_digest or digests != {actual_digest}:
            raise SystemExit("legacy browser 派生证据与主批次摘要不一致。")
        for name, artifact in legacy_derived.items():
            expected_coverage = LEGACY_BROWSER_CHECK_COVERAGE[name]
            if artifact.get("check") != name or artifact.get("status") != "pass":
                raise SystemExit(f"legacy browser 派生证据字段不一致：{name}。")
            if artifact.get("implementation_commit") != implementation_commit or artifact.get(
                "source_hash"
            ) != approved_hash:
                raise SystemExit(f"legacy browser 派生证据已过期：{name}。")
            if artifact.get("single_chain_invocation") is not True or artifact.get(
                "covers"
            ) != [expected_coverage]:
                raise SystemExit(f"legacy browser 派生证据覆盖范围不一致：{name}。")
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
