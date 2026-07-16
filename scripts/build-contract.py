#!/usr/bin/env python3
"""Write and validate the lifecycle contract stored in module .work-meta.json.

The contract is the deterministic handoff shared by design, build, automatic
finalize, recovery, and post-land documentation.  It records framework choices
and PM-approved product deltas so no stage has to infer state from cwd or branch
shape.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
import subprocess

from _lib.project_definition import ProjectDefinitionError, load_project_definition
from _lib.ready_contract import (
    ReadyContractError,
    approved_target_paths,
    classify_dirty_paths,
    load_context_pack,
    normalize_paths,
    ready_currentness,
    validate_ready_pack,
)


VALID_MODES = {"worktree", "main"}
VALID_EXECUTORS = {"claude-code", "codex", "cursor-agent", "opencode", "manual", "native"}
VALID_TARGET_KINDS = {"prototype", "product"}
VALID_LIFECYCLE_STATES = {
    "designing",
    "ready_to_build",
    "building",
    "iterating",
    "final_check",
    "landed",
    "documenting",
    "complete",
}
VALID_DOCS_STATUSES = {"pending", "complete", "failed"}
PASSING_EVIDENCE_STATUSES = {"pass", "passed", "clean", "built"}
LIMITED_EVIDENCE_STATUSES = {"limited", "skipped", "blocked", "needs-review"}
VALID_EVIDENCE_STATUSES = {
    *PASSING_EVIDENCE_STATUSES,
    *LIMITED_EVIDENCE_STATUSES,
    "fail",
}
EVIDENCE_LABELS = {
    "browser-smoke": "浏览器主动 smoke",
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


def canonical_json(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )


def sha256_value(value: object) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


def normalize_string_list(values: list[str] | None) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values or []:
        item = value.strip()
        if item and item not in seen:
            seen.add(item)
            result.append(item)
    return result


def contract_version(build: dict) -> int:
    value = build.get("contract_version", 1)
    try:
        return int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"build.contract_version 必须是整数: {value}")


def ensure_v2_shape(build: dict) -> None:
    if contract_version(build) < 2:
        return
    target = build.get("target")
    if not isinstance(target, dict) or target.get("kind") not in VALID_TARGET_KINDS:
        raise SystemExit("build.target.kind 必须是 prototype 或 product。")
    if not isinstance(target.get("paths", []), list) or not isinstance(
        target.get("entrypoints", []), list
    ):
        raise SystemExit("build.target.paths / entrypoints 必须是数组。")
    state = build.get("lifecycle_state")
    if state not in VALID_LIFECYCLE_STATES:
        raise SystemExit(
            "build.lifecycle_state 不合法："
            f"{state}（允许 {', '.join(sorted(VALID_LIFECYCLE_STATES))}）。"
        )
    if not isinstance(build.get("design_revision"), int) or build["design_revision"] < 1:
        raise SystemExit("build.design_revision 必须是正整数。")
    if not optional(build.get("approved_source_hash")):
        raise SystemExit("build 合同缺少 approved_source_hash。")
    acceptance = build.get("acceptance")
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    required_checks = acceptance.get("required_checks", [])
    if (
        not isinstance(required_checks, list)
        or not required_checks
        or any(not isinstance(item, str) or not item.strip() for item in required_checks)
    ):
        raise SystemExit("build.acceptance.required_checks 必须是非空字符串数组。")
    if len(set(required_checks)) != len(required_checks):
        raise SystemExit("build.acceptance.required_checks 不能包含重复检查。")
    if not isinstance(acceptance.get("evidence", []), list):
        raise SystemExit("build.acceptance.evidence 必须是数组。")
    docs_status = build.get("docs_status")
    if docs_status not in VALID_DOCS_STATUSES:
        raise SystemExit(
            f"build.docs_status 不合法：{docs_status}（允许 {', '.join(sorted(VALID_DOCS_STATUSES))}）。"
        )


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


def evidence_exception_for(build: dict, check_name: str) -> bool:
    exc = audit_exception(build)
    if not exc or not exc.get("accepted_at") or not exc.get("reason"):
        return False
    checks = exc.get("checks")
    if checks is None:
        return True  # v1 compatibility: one exception covered the browser audit bundle
    return isinstance(checks, list) and check_name in checks


def clear_review_ready(build: dict) -> None:
    """Invalidate the pre-acceptance readiness snapshot without deleting evidence."""

    acceptance = build.setdefault("acceptance", {"required_checks": [], "evidence": []})
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    acceptance["ready_at"] = None
    acceptance["ready_commit"] = None
    acceptance["ready_source_hash"] = None


def validate_review_ready(build: dict) -> None:
    """Require a readiness snapshot bound to the current source and implementation."""

    acceptance = build.get("acceptance")
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    ready_at = optional(acceptance.get("ready_at"))
    ready_commit = optional(acceptance.get("ready_commit"))
    ready_source_hash = optional(acceptance.get("ready_source_hash"))
    if not ready_at or not ready_commit or not ready_source_hash:
        raise SystemExit(
            "当前实现尚未形成验收就绪快照：先在 build 阶段对候选提交完成全部 required checks，"
            "再运行 review-ready；build-close 不在 PM 定稿后临时补实现或首次跑完整验收。"
        )
    if ready_commit != optional(build.get("implementation_commit")):
        raise SystemExit("验收就绪快照已过期：implementation commit 已变化，请回 build 重新检查。")
    if ready_source_hash != optional(build.get("approved_source_hash")):
        raise SystemExit("验收就绪快照已过期：approved source 已变化，请回 build 重新检查。")


def validate_fresh_evidence(module_dir: Path, build: dict) -> None:
    """Validate v2 adaptive acceptance and evidence freshness."""

    acceptance = build.get("acceptance")
    assert isinstance(acceptance, dict)
    required = [str(value) for value in acceptance.get("required_checks", [])]
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
        if name == "browser-smoke" and status not in PASSING_EVIDENCE_STATUSES:
            raise SystemExit(
                "UI 验收缺少可用的主动浏览器能力：browser-smoke 必须通过，"
                "v2 不能用 exception 跳过。请启用 gstack/browse、browser 或 Playwright 后重跑。"
            )
        if status in PASSING_EVIDENCE_STATUSES:
            pass
        elif status in LIMITED_EVIDENCE_STATUSES:
            if evidence_exception_for(build, name):
                pass
            else:
                raise SystemExit(
                    f"build 验收存在受限/跳过/失败/阻塞项：{label}。"
                    "必须记录 PM 明确接受该缺口后才能落地主线。"
                )
        elif name == "behavior" and status == "fail":
            raise SystemExit("行为审未通过：不能落地主线。请先修到通过。")
        else:
            raise SystemExit(f"验收证据 {name} 未通过：status={status or '<empty>'}。")
        artifact = optional(item.get("artifact")) if isinstance(item.get("artifact"), str) else None
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


def current_source_hash(build: dict, delta: dict | None = None) -> str:
    previous = str(build.get("approved_source_hash", ""))
    if delta is None:
        return previous
    return sha256_value({"previous": previous, "delta": delta})


def _path_within(path: str, parent: str) -> bool:
    if parent == ".":
        return True
    return path == parent or path.startswith(parent.rstrip("/") + "/")


def validate_target_paths(repo_root: Path, values: list[str]) -> list[str]:
    target_paths = normalize_paths(values, "approved_target.paths")
    try:
        definition = load_project_definition(repo_root / ".pm-workflow" / "project.yml")
    except ProjectDefinitionError as exc:
        raise SystemExit(str(exc)) from exc
    root = str(definition["implementation"]["root"])
    entrypoints = [str(value) for value in definition["implementation"]["entrypoints"]]
    for path in target_paths:
        if not _path_within(path, root):
            raise SystemExit(f"目标路径不在 project.yml implementation.root 内：{path}")
        if not any(_path_within(path, entrypoint) for entrypoint in entrypoints):
            raise SystemExit(f"目标路径没有命中 project.yml implementation.entrypoints：{path}")
    return target_paths


def _validate_ready_for_start(module_dir: Path, meta: dict) -> dict | None:
    if str(meta.get("lifecycle_state") or "") != "ready_to_build":
        return None
    repo_root = repo_root_for(module_dir)
    result = ready_currentness(repo_root, module_dir, meta)
    if result.get("state") != "current":
        raise SystemExit(result.get("reason") or "ready 建造依据已经过期。")
    return result


def ensure_target_paths_clean(repo_root: Path, target_paths: list[str]) -> dict:
    result = classify_dirty_paths(repo_root, target_paths)
    if result["overlapping"]:
        paths = "\n".join(f"- {path}" for path in result["overlapping"])
        raise SystemExit(
            "本轮目标路径已有未提交改动，不能默认带入或丢弃：\n"
            f"{paths}\n请先明确这些改动是否属于本轮，并固定到可恢复的提交点后再开始 build。"
        )
    return result


def cmd_start(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    path = meta_path(module_dir)
    if path.exists():
        meta = read_meta(module_dir)
    else:
        module_dir.mkdir(parents=True, exist_ok=True)
        meta = default_meta(module_dir, args.branch)

    ready_result = _validate_ready_for_start(module_dir, meta)

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
    target_kind = optional(args.target_kind)
    if target_kind not in VALID_TARGET_KINDS:
        raise SystemExit(f"target.kind 必须是 {' / '.join(sorted(VALID_TARGET_KINDS))}: {target_kind}")
    target_paths = normalize_string_list(args.target_path)
    if not target_paths:
        raise SystemExit("v2 build 必须显式记录 acceptance profile 对应的 target.paths。")
    if ready_result is not None and target_paths != ready_result["target_paths"]:
        raise SystemExit("build target paths 与 design 批准范围不一致；请勿在 build 开工时临时改写目标。")
    if ready_result is not None:
        ensure_target_paths_clean(repo_root_for(module_dir), ready_result["target_paths"])
    entrypoints = normalize_string_list(args.entrypoint)
    if not entrypoints:
        raise SystemExit("v2 build 必须记录 project.yml 声明的 implementation.entrypoints。")
    source_hash = optional(args.approved_source_hash) or optional(meta.get("approved_source_hash"))
    if ready_result is not None and source_hash != ready_result["approved_source_hash"]:
        raise SystemExit("build 使用的 approved_source_hash 与 design 批准依据不一致。")
    if not source_hash:
        anchor_path = Path(args.anchor).expanduser()
        repo_root = repo_root_for(module_dir)
        anchor_path = anchor_path if anchor_path.is_absolute() else repo_root / anchor_path
        if anchor_path.is_file():
            source_hash = hashlib.sha256(anchor_path.read_bytes()).hexdigest()
        else:
            source_hash = sha256_value({"anchor": args.anchor, "baseline": optional(args.baseline_sha)})
    required_checks = normalize_string_list(args.required_check)
    if not required_checks:
        raise SystemExit("v2 build 必须记录 acceptance profile 生成的 required_checks。")

    build = {
        "contract_version": 2,
        "anchor": args.anchor,
        "target": {
            "kind": target_kind,
            "paths": target_paths,
            "entrypoints": entrypoints,
        },
        "approved_source_hash": source_hash,
        "design_revision": args.design_revision or int(meta.get("design_revision") or 1),
        "accepted_deltas": [],
        "lifecycle_state": "building",
        "mode": mode,
        "executor": executor,
        "branch": branch,
        "worktree": worktree,
        "baseline_sha": optional(args.baseline_sha),
        "audit_dir": optional(args.audit_dir),
        "started_at": now_iso(),
        "implementation_commit": None,
        "pm_accepted_at": None,
        "acceptance": {
            "required_checks": required_checks,
            "evidence": [],
            "ready_at": None,
            "ready_commit": None,
            "ready_source_hash": None,
        },
        "docs_status": "pending",
    }
    builder_profile = optional(args.builder_profile)
    if builder_profile:
        build["builder_profile"] = builder_profile
    if builder:
        build["builder"] = builder

    meta["status"] = "active"
    meta["stage"] = 2
    meta["lifecycle_state"] = "building"
    meta["design_revision"] = build["design_revision"]
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
        raise SystemExit("缺少 build 合同：请先由 /pmai-build 自动生成目标、建造依据和验收要求，再继续。")
    return build


def cmd_designing(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    module_dir.mkdir(parents=True, exist_ok=True)
    path = meta_path(module_dir)
    meta = read_meta(module_dir) if path.exists() else default_meta(module_dir)
    meta["status"] = "active"
    meta["stage"] = 1
    meta["lifecycle_state"] = "designing"
    write_meta(module_dir, meta)
    print(json.dumps(meta, ensure_ascii=False))


def cmd_ready(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    path = meta_path(module_dir)
    meta = read_meta(module_dir) if path.exists() else default_meta(module_dir)
    source_hash = optional(args.approved_source_hash)
    checkpoint = optional(args.checkpoint_commit)
    if not source_hash or not checkpoint:
        raise SystemExit("ready 必须提供 approved_source_hash 和 checkpoint_commit。")
    repo_root = repo_root_for(module_dir)
    pack = load_context_pack(Path(args.context_pack))
    expected_module = module_dir.expanduser().resolve().relative_to(repo_root.resolve()).as_posix()
    if pack.get("module") != expected_module:
        raise SystemExit("ready 使用的 context pack 不属于当前模块。")
    if str(pack.get("source_hash") or "") != source_hash:
        raise SystemExit("ready 的 approved_source_hash 与最新 context pack 不一致。")
    target_paths = validate_target_paths(repo_root, args.target_path)
    meta["status"] = "active"
    meta["stage"] = 1
    meta["lifecycle_state"] = "ready_to_build"
    meta["design_revision"] = args.design_revision
    meta["approved_source_hash"] = source_hash
    meta["design_checkpoint_commit"] = checkpoint
    meta["approved_target"] = {"paths": target_paths}
    write_meta(module_dir, meta)
    print(json.dumps(meta, ensure_ascii=False))


def cmd_validate_ready(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    repo_root = repo_root_for(module_dir)
    try:
        if args.context_pack:
            result = validate_ready_pack(
                repo_root,
                module_dir,
                meta,
                load_context_pack(Path(args.context_pack)),
            )
        else:
            result = ready_currentness(repo_root, module_dir, meta)
            if result.get("state") != "current":
                raise ReadyContractError(result.get("reason") or "ready 建造依据已经过期。")
    except ReadyContractError as exc:
        raise SystemExit(str(exc)) from exc
    print(json.dumps(result, ensure_ascii=False))


def cmd_check_dirty(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    repo_root = repo_root_for(module_dir)
    try:
        target_paths = approved_target_paths(meta)
        result = ensure_target_paths_clean(repo_root, target_paths)
    except ReadyContractError as exc:
        raise SystemExit(str(exc)) from exc
    print(json.dumps(result, ensure_ascii=False))


def cmd_commit(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    commit = optional(args.implementation_commit)
    if not commit:
        raise SystemExit("必须提供 implementation_commit")
    if contract_version(build) >= 2 and build.get("lifecycle_state") not in {
        "building",
        "iterating",
    }:
        raise SystemExit("只有 building / iterating 状态可以记录新的实现提交。")
    previous_commit = optional(build.get("implementation_commit"))
    if contract_version(build) >= 2 and previous_commit != commit:
        acceptance = build.setdefault("acceptance", {"required_checks": [], "evidence": []})
        if not isinstance(acceptance, dict):
            raise SystemExit("build.acceptance 必须是对象。")
        acceptance["evidence"] = []
        clear_review_ready(build)
        build["pm_accepted_at"] = None
    build["implementation_commit"] = commit
    build["implementation_committed_at"] = now_iso()
    if contract_version(build) >= 2:
        build["lifecycle_state"] = "iterating"
        meta["lifecycle_state"] = "iterating"
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_accept(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    if contract_version(build) >= 2 and build.get("lifecycle_state") not in {
        "iterating",
        "final_check",
    }:
        raise SystemExit("只有 PM 看过构建结果后才能进入 final_check。")
    if contract_version(build) >= 2:
        ensure_v2_shape(build)
        validate_review_ready(build)
    accepted_at = optional(args.accepted_at) or now_iso()
    build["pm_accepted_at"] = accepted_at
    if contract_version(build) >= 2:
        build["lifecycle_state"] = "final_check"
        meta["lifecycle_state"] = "final_check"
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
    if contract_version(build) >= 2 and build.get("lifecycle_state") not in {
        "iterating",
        "final_check",
    }:
        raise SystemExit("只有 iterating / final_check 状态可以记录定稿。")
    previous_commit = optional(build.get("implementation_commit"))
    if contract_version(build) >= 2:
        if previous_commit != commit:
            raise SystemExit(
                "v2 定稿不能同时换 implementation commit：先用 commit 记录候选提交，"
                "完成 required checks 和 review-ready，再记录 PM 定稿。"
            )
        ensure_v2_shape(build)
        validate_review_ready(build)
    accepted_at = optional(args.accepted_at) or now_iso()
    build["implementation_commit"] = commit
    build["implementation_committed_at"] = now_iso()
    build["pm_accepted_at"] = accepted_at
    if contract_version(build) >= 2:
        build["lifecycle_state"] = "final_check"
        meta["lifecycle_state"] = "final_check"
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_audit_exception(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    reason = optional(args.reason)
    if not reason:
        raise SystemExit("必须提供 PM 接受验收受限/跳过项的原因")
    checks = normalize_string_list(args.check)
    if contract_version(build) >= 2:
        if not checks:
            raise SystemExit("v2 audit-exception 必须用 --check 点名受限检查。")
        if "browser-smoke" in checks:
            raise SystemExit("v2 UI 验收不能跳过主动浏览器能力；browser-smoke 不允许 exception。")
    build["audit_exception"] = {
        "accepted_at": optional(args.accepted_at) or now_iso(),
        "reason": reason,
    }
    if checks:
        build["audit_exception"]["checks"] = checks
    if contract_version(build) >= 2:
        clear_review_ready(build)
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_add_delta(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    if contract_version(build) < 2:
        raise SystemExit("accepted delta 只适用于 build contract v2。")
    summary = optional(args.summary)
    if not summary:
        raise SystemExit("必须提供 delta summary。")
    delta = {
        "kind": optional(args.kind) or "product-behavior",
        "summary": summary,
        "affected_surfaces": normalize_string_list(args.affected_surface),
        "accepted_at": optional(args.accepted_at) or now_iso(),
    }
    deltas = build.setdefault("accepted_deltas", [])
    if not isinstance(deltas, list):
        raise SystemExit("build.accepted_deltas 必须是数组。")
    deltas.append(delta)
    build["design_revision"] = int(build.get("design_revision", 1)) + 1
    build["approved_source_hash"] = current_source_hash(build, delta)
    acceptance = build.setdefault("acceptance", {"required_checks": [], "evidence": []})
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    acceptance["evidence"] = []
    clear_review_ready(build)
    build["implementation_commit"] = None
    build["pm_accepted_at"] = None
    build["lifecycle_state"] = "iterating"
    meta["lifecycle_state"] = "iterating"
    meta["design_revision"] = build["design_revision"]
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_record_evidence(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    if contract_version(build) < 2:
        raise SystemExit("fresh evidence 只适用于 build contract v2。")
    name = optional(args.name)
    status = optional(args.status)
    commit = optional(args.commit) or optional(build.get("implementation_commit"))
    source_hash = optional(args.source_hash) or optional(build.get("approved_source_hash"))
    if not name or not status or not commit or not source_hash:
        raise SystemExit("record-evidence 必须有 name、status、commit 和 source_hash。")
    if status not in VALID_EVIDENCE_STATUSES:
        raise SystemExit(
            "record-evidence status 不合法："
            f"{status}（允许 {', '.join(sorted(VALID_EVIDENCE_STATUSES))}）。"
        )
    item = {
        "name": name,
        "status": status,
        "source_hash": source_hash,
        "commit": commit,
        "checked_at": optional(args.checked_at) or now_iso(),
        "artifact": optional(args.artifact),
    }
    acceptance = build.setdefault("acceptance", {"required_checks": [], "evidence": []})
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    evidence = acceptance.setdefault("evidence", [])
    if not isinstance(evidence, list):
        raise SystemExit("build.acceptance.evidence 必须是数组。")
    acceptance["evidence"] = [entry for entry in evidence if entry.get("name") != name]
    acceptance["evidence"].append(item)
    clear_review_ready(build)
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(item, ensure_ascii=False))


def cmd_review_ready(args: argparse.Namespace) -> None:
    """Freeze a fully checked candidate before PM finalization."""

    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    if contract_version(build) < 2:
        raise SystemExit("review-ready 只适用于 build contract v2。")
    if build.get("lifecycle_state") not in {"iterating", "final_check"}:
        raise SystemExit("只有 iterating / final_check 的候选实现可以标记为验收就绪。")
    if not optional(build.get("implementation_commit")):
        raise SystemExit("候选实现尚未记录 implementation_commit，不能标记为验收就绪。")
    ensure_v2_shape(build)
    validate_fresh_evidence(module_dir, build)
    acceptance = build["acceptance"]
    acceptance["ready_at"] = optional(args.checked_at) or now_iso()
    acceptance["ready_commit"] = build["implementation_commit"]
    acceptance["ready_source_hash"] = build["approved_source_hash"]
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(acceptance, ensure_ascii=False))


def transition(
    module_dir: Path,
    state: str,
    docs_status: str | None = None,
    reason: str | None = None,
    allowed_from: set[str] | None = None,
) -> dict:
    if state not in VALID_LIFECYCLE_STATES:
        raise SystemExit(f"未知 lifecycle state: {state}")
    meta = read_meta(module_dir)
    build = require_build(meta)
    if contract_version(build) < 2:
        raise SystemExit("显式 lifecycle transition 只适用于 build contract v2。")
    current = str(build.get("lifecycle_state") or "")
    if allowed_from is not None and current not in allowed_from:
        raise SystemExit(
            f"lifecycle 不能从 {current or '<empty>'} 进入 {state}；"
            f"允许来源：{', '.join(sorted(allowed_from))}。"
        )
    build["lifecycle_state"] = state
    meta["lifecycle_state"] = state
    if docs_status is not None:
        if docs_status not in VALID_DOCS_STATUSES:
            raise SystemExit(f"未知 docs status: {docs_status}")
        build["docs_status"] = docs_status
        build["docs_updated_at"] = now_iso()
    if reason:
        build["docs_failure_reason"] = reason
    elif docs_status == "complete":
        build.pop("docs_failure_reason", None)
    meta["build"] = build
    write_meta(module_dir, meta)
    return build


def cmd_iterating(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    if contract_version(build) < 2:
        raise SystemExit("显式 lifecycle transition 只适用于 build contract v2。")
    current = str(build.get("lifecycle_state") or "")
    if current not in {"iterating", "final_check"}:
        raise SystemExit(
            f"lifecycle 不能从 {current or '<empty>'} 进入 iterating；"
            "允许来源：final_check、iterating。"
        )
    build["lifecycle_state"] = "iterating"
    build["pm_accepted_at"] = None
    clear_review_ready(build)
    meta["lifecycle_state"] = "iterating"
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_landed(args: argparse.Namespace) -> None:
    build = transition(
        Path(args.module_dir),
        "landed",
        "pending",
        allowed_from={"final_check"},
    )
    build["landed_commit"] = optional(args.landed_commit)
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    meta["build"] = build
    write_meta(module_dir, meta)
    print(json.dumps(build, ensure_ascii=False))


def cmd_docs_start(args: argparse.Namespace) -> None:
    print(
        json.dumps(
            transition(
                Path(args.module_dir),
                "documenting",
                "pending",
                allowed_from={"landed", "documenting"},
            ),
            ensure_ascii=False,
        )
    )


def cmd_docs_complete(args: argparse.Namespace) -> None:
    print(
        json.dumps(
            transition(
                Path(args.module_dir),
                "documenting",
                "complete",
                allowed_from={"landed", "documenting"},
            ),
            ensure_ascii=False,
        )
    )


def cmd_docs_fail(args: argparse.Namespace) -> None:
    reason = optional(args.reason)
    if not reason:
        raise SystemExit("必须提供文档失败原因。")
    print(
        json.dumps(
            transition(
                Path(args.module_dir),
                "landed",
                "failed",
                reason=reason,
                allowed_from={"landed", "documenting"},
            ),
            ensure_ascii=False,
        )
    )


def cmd_validate_docs(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    if contract_version(build) < 2:
        raise SystemExit("validate-docs 只适用于 build contract v2。")
    if build.get("lifecycle_state") not in {"landed", "documenting"}:
        raise SystemExit("实现尚未落到 main，不能完成正式文档更新。")
    if build.get("docs_status") != "complete":
        raise SystemExit("正式文档尚未通过覆盖与一致性检查。")
    print(json.dumps(build, ensure_ascii=False))


def cmd_validate_close(args: argparse.Namespace) -> None:
    module_dir = Path(args.module_dir)
    meta = read_meta(module_dir)
    build = require_build(meta)
    version = contract_version(build)
    ensure_v2_shape(build)

    mode = build.get("mode")
    executor = build.get("executor")
    validate_mode_executor(mode, executor)

    if not build.get("anchor"):
        raise SystemExit("build 合同缺少 anchor，不能收尾。")
    if not build.get("implementation_commit"):
        raise SystemExit("build 合同缺少 implementation_commit：实现提交尚未记录，不能收尾。")
    if not build.get("pm_accepted_at"):
        raise SystemExit("build 合同缺少 pm_accepted_at：PM 验收未记录，不能收尾。")
    if version >= 2 and build.get("lifecycle_state") != "final_check":
        raise SystemExit(
            "build 尚未进入 final_check：只有 PM 明确定稿并完成最终检查后才能落地主线。"
        )
    if mode == "worktree" and not build.get("branch"):
        raise SystemExit("build 合同要求隔离环境，但缺少 branch。")
    if mode == "main" and build.get("branch") not in (None, "", "main", "master"):
        raise SystemExit("build 合同是 main 模式，但 branch 不是 main/master，不能按主线直收。")
    builder = build.get("builder")
    if builder is not None:
        if not isinstance(builder, dict):
            raise SystemExit("build 合同里的 builder 必须是对象。")
        validate_builder(builder)
    if version >= 2:
        validate_review_ready(build)
        validate_fresh_evidence(module_dir, build)
    else:
        validate_audit_evidence(module_dir, build)

    print(json.dumps(build, ensure_ascii=False))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    designing = sub.add_parser("designing", help="mark the module as being discussed")
    designing.add_argument("module_dir")
    designing.set_defaults(func=cmd_designing)

    ready = sub.add_parser("ready", help="record the approved and committed design checkpoint")
    ready.add_argument("module_dir")
    ready.add_argument("--approved-source-hash", required=True)
    ready.add_argument("--checkpoint-commit", required=True)
    ready.add_argument("--context-pack", required=True)
    ready.add_argument("--target-path", action="append", required=True)
    ready.add_argument("--design-revision", type=int, default=1)
    ready.set_defaults(func=cmd_ready)

    validate_ready = sub.add_parser("validate-ready", help="verify that an approved design is current")
    validate_ready.add_argument("module_dir")
    validate_ready.add_argument("--context-pack")
    validate_ready.set_defaults(func=cmd_validate_ready)

    check_dirty = sub.add_parser("check-dirty", help="block target-overlapping uncommitted changes")
    check_dirty.add_argument("module_dir")
    check_dirty.set_defaults(func=cmd_check_dirty)

    start = sub.add_parser("start", help="record the adaptive build contract before implementation")
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
    start.add_argument("--target-kind", choices=sorted(VALID_TARGET_KINDS), required=True)
    start.add_argument("--target-path", action="append", required=True)
    start.add_argument("--entrypoint", action="append", required=True)
    start.add_argument("--approved-source-hash")
    start.add_argument("--design-revision", type=int, default=1)
    start.add_argument("--required-check", action="append", required=True)
    start.set_defaults(func=cmd_start)

    commit = sub.add_parser("commit", help="record the implementation commit produced by build")
    commit.add_argument("module_dir")
    commit.add_argument("--implementation-commit", required=True)
    commit.set_defaults(func=cmd_commit)

    accept = sub.add_parser("accept", help="record PM acceptance before automatic final_check")
    accept.add_argument("module_dir")
    accept.add_argument("--accepted-at")
    accept.set_defaults(func=cmd_accept)

    complete = sub.add_parser(
        "complete",
        help="compatibility command: accept the already recorded and review-ready implementation commit",
    )
    complete.add_argument("module_dir")
    complete.add_argument("--implementation-commit", required=True)
    complete.add_argument("--accepted-at")
    complete.set_defaults(func=cmd_complete)

    audit_exception = sub.add_parser(
        "audit-exception",
        help="record PM acceptance for named limited checks; v2 browser-smoke cannot be excepted",
    )
    audit_exception.add_argument("module_dir")
    audit_exception.add_argument("--reason", required=True)
    audit_exception.add_argument("--accepted-at")
    audit_exception.add_argument("--check", action="append", default=[])
    audit_exception.set_defaults(func=cmd_audit_exception)

    delta = sub.add_parser("add-delta", help="record a PM-accepted product change and invalidate evidence")
    delta.add_argument("module_dir")
    delta.add_argument("--kind", default="product-behavior")
    delta.add_argument("--summary", required=True)
    delta.add_argument("--affected-surface", action="append", default=[])
    delta.add_argument("--accepted-at")
    delta.set_defaults(func=cmd_add_delta)

    evidence = sub.add_parser("record-evidence", help="record one check bound to source hash and commit")
    evidence.add_argument("module_dir")
    evidence.add_argument("--name", required=True)
    evidence.add_argument("--status", required=True)
    evidence.add_argument("--source-hash")
    evidence.add_argument("--commit")
    evidence.add_argument("--checked-at")
    evidence.add_argument("--artifact")
    evidence.set_defaults(func=cmd_record_evidence)

    review_ready = sub.add_parser(
        "review-ready",
        help="validate all fresh evidence and freeze the candidate before PM finalization",
    )
    review_ready.add_argument("module_dir")
    review_ready.add_argument("--checked-at")
    review_ready.set_defaults(func=cmd_review_ready)

    iterating = sub.add_parser("iterating", help="return a failed final check to the review loop")
    iterating.add_argument("module_dir")
    iterating.set_defaults(func=cmd_iterating)

    landed = sub.add_parser("landed", help="record that implementation is now on main")
    landed.add_argument("module_dir")
    landed.add_argument("--landed-commit")
    landed.set_defaults(func=cmd_landed)

    docs_start = sub.add_parser("docs-start", help="start post-land documentation compilation")
    docs_start.add_argument("module_dir")
    docs_start.set_defaults(func=cmd_docs_start)

    docs_complete = sub.add_parser("docs-complete", help="record successful documentation coverage")
    docs_complete.add_argument("module_dir")
    docs_complete.set_defaults(func=cmd_docs_complete)

    docs_fail = sub.add_parser("docs-fail", help="record recoverable post-land documentation failure")
    docs_fail.add_argument("module_dir")
    docs_fail.add_argument("--reason", required=True)
    docs_fail.set_defaults(func=cmd_docs_fail)

    validate_docs = sub.add_parser("validate-docs", help="validate that post-land docs may be committed")
    validate_docs.add_argument("module_dir")
    validate_docs.set_defaults(func=cmd_validate_docs)

    validate = sub.add_parser("validate-close", help="validate that implementation may land (v1 alias retained)")
    validate.add_argument("module_dir")
    validate.set_defaults(func=cmd_validate_close)

    validate_land = sub.add_parser("validate-land", help="validate PM acceptance and fresh evidence")
    validate_land.add_argument("module_dir")
    validate_land.set_defaults(func=cmd_validate_close)

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
