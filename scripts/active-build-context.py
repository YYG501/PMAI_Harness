#!/usr/bin/env python3
"""Read and validate the execution context for the current active PMAI build."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path, PurePosixPath

_SCRIPTS_DIR = str(Path(__file__).resolve().parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.delivery_policy import (  # noqa: E402
    delivery_policy_for,
    delivery_policy_hash,
    validate_delivery_policy,
)
from _lib.project_definition import ProjectDefinitionError, load_project_definition  # noqa: E402
from _lib.state import StateReadError, get_overall_state  # noqa: E402
from _lib.work_contract import (  # noqa: E402
    WorkContractError,
    normalize_work_contract,
    normalize_work_state,
)


ACTIVE_BUILD_LIFECYCLES = {"building", "iterating", "final_check"}


def _blocking_route(work_view: dict) -> str:
    work_dir = Path(work_view.get("work_dir") or ".").resolve()
    try:
        work_root = _work_repo_root(work_dir)
    except ValueError:
        return "pmai-design"
    result = subprocess.run(
        [
            sys.executable,
            str(Path(_SCRIPTS_DIR) / "context-pack.py"),
            "--repo-root",
            str(work_root),
            "--module",
            str(work_dir),
            "--route-only",
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return "pmai-design"
    route = payload.get("route") if isinstance(payload, dict) else None
    if route == "pmai-proposal":
        return "pmai-proposal"
    return "pmai-design"


def find_repo_root() -> Path:
    try:
        common = subprocess.check_output(
            ["git", "rev-parse", "--git-common-dir"], text=True
        ).strip()
        if common and common != ".git":
            return Path(common).resolve().parent
    except Exception:
        pass
    try:
        return Path(
            subprocess.check_output(
                ["git", "rev-parse", "--show-toplevel"], text=True
            ).strip()
        )
    except Exception:
        return Path.cwd()


def _lifecycle(meta: dict) -> str:
    try:
        contract = normalize_work_state(meta)
        if "stage_lifecycle" in contract.compatibility:
            return ""
        return contract.lifecycle_state
    except WorkContractError:
        return ""


def _work_display_name(work_view: dict) -> str:
    meta = work_view.get("meta") or {}
    return str(
        meta.get("name")
        or meta.get("id")
        or Path(work_view.get("work_dir") or ".").name
    )


def _active_build_currentness(work_dir: Path) -> dict:
    script = Path(_SCRIPTS_DIR) / "build-contract.py"
    result = subprocess.run(
        [sys.executable, str(script), "validate-currentness", str(work_dir)],
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 0:
        try:
            payload = json.loads(result.stdout)
        except json.JSONDecodeError:
            payload = {}
        return {
            "state": "current",
            **(
                {"legacy_recovery": payload["legacy_recovery"]}
                if isinstance(payload, dict) and payload.get("legacy_recovery")
                else {}
            ),
        }
    reason = result.stderr.strip() or result.stdout.strip() or "无法校验当前建造依据。"
    if reason.startswith("❌ "):
        reason = reason[2:]
    return {"state": "stale", "reason": reason}


def _work_repo_root(work_dir: Path) -> Path:
    try:
        value = subprocess.check_output(
            ["git", "-C", str(work_dir), "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception as exc:
        raise ValueError(f"无法定位 active build 所在仓库：{work_dir}") from exc
    if not value:
        raise ValueError(f"无法定位 active build 所在仓库：{work_dir}")
    return Path(value).resolve()


def _contract_path(value: object, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label} 必须是非空仓内相对路径。")
    normalized = value.strip()
    path = PurePosixPath(normalized)
    if "\\" in normalized or path.is_absolute() or ".." in path.parts:
        raise ValueError(f"{label} 必须是仓内相对 POSIX 路径：{normalized}")
    return normalized


def _contract_paths(value: object, label: str, *, required: bool = True) -> list[str]:
    if not isinstance(value, list) or (required and not value):
        suffix = "非空" if required else ""
        raise ValueError(f"{label} 必须是{suffix}路径数组。")
    normalized = [
        _contract_path(item, f"{label}[{index}]") for index, item in enumerate(value)
    ]
    if len(set(normalized)) != len(normalized):
        raise ValueError(f"{label} 不能包含重复路径。")
    return normalized


def _path_within(path: str, parent: str) -> bool:
    normalized_path = path.rstrip("/")
    normalized_parent = parent.rstrip("/")
    if normalized_parent in {"", "."}:
        return True
    return normalized_path == normalized_parent or normalized_path.startswith(
        normalized_parent + "/"
    )


def _build_execution_context(work_view: dict) -> dict:
    work_dir = Path(work_view["work_dir"]).resolve()
    work_root = _work_repo_root(work_dir)
    meta = work_view.get("meta")
    if not isinstance(meta, dict):
        raise ValueError("active work metadata 必须是对象。")
    build = meta.get("build")
    if not isinstance(build, dict):
        raise ValueError("active work 缺少 build contract。")

    try:
        contract = normalize_work_contract(meta)
    except WorkContractError as exc:
        raise ValueError(str(exc)) from exc
    lifecycle = contract.lifecycle_state
    if lifecycle not in ACTIVE_BUILD_LIFECYCLES:
        raise ValueError(f"active build lifecycle 不可续接：{lifecycle or 'missing'}")

    contract_version = contract.contract_version
    assert contract_version is not None
    if contract_version < 2:
        raise ValueError("active build contract 过旧；请通过 /pmai-build 恢复后再继续检查。")

    currentness = _active_build_currentness(work_dir)
    if currentness.get("state") != "current":
        raise ValueError(
            str(currentness.get("reason") or "当前建造依据已经过期；请先重新确认。")
        )

    target = build.get("target")
    if not isinstance(target, dict):
        raise ValueError("build.target 必须是对象。")
    target_kind = target.get("kind")
    if target_kind not in {"prototype", "product"}:
        raise ValueError("build.target.kind 必须是 prototype 或 product。")
    target_paths = _contract_paths(target.get("paths"), "build.target.paths")
    target_entrypoints = _contract_paths(
        target.get("entrypoints"), "build.target.entrypoints"
    )
    anchor = _contract_path(build.get("anchor"), "build.anchor")
    if not (work_root / anchor).is_file():
        raise ValueError(f"build.anchor 指向的文件不存在：{anchor}")

    definition_path = work_root / ".pm-workflow" / "project.yml"
    try:
        definition = load_project_definition(definition_path)
    except ProjectDefinitionError as exc:
        raise ValueError(str(exc)) from exc
    if definition["project"]["type"] != target_kind:
        raise ValueError("build.target.kind 与 project.yml 的 project.type 不一致。")
    project_entrypoints = list(definition["implementation"]["entrypoints"])
    if target_entrypoints != project_entrypoints:
        raise ValueError(
            "build.target.entrypoints 与 project.yml 的 implementation.entrypoints 不一致。"
        )
    implementation_root = definition["implementation"]["root"]
    for target_path in target_paths:
        if not _path_within(target_path, implementation_root):
            raise ValueError(
                f"build.target.paths 超出 project.yml implementation.root：{target_path}"
            )
        if not any(
            _path_within(target_path, entrypoint) for entrypoint in project_entrypoints
        ):
            raise ValueError(
                f"build.target.paths 未命中 project.yml implementation.entrypoints：{target_path}"
            )

    approved_source_hash = build.get("approved_source_hash")
    if not isinstance(approved_source_hash, str) or not approved_source_hash.strip():
        raise ValueError("build contract 缺少 approved_source_hash。")
    design_revision = build.get("design_revision")
    if (
        not isinstance(design_revision, int)
        or isinstance(design_revision, bool)
        or design_revision < 1
    ):
        raise ValueError("build.design_revision 必须是正整数。")

    if contract_version >= 3:
        try:
            policy = validate_delivery_policy(build.get("delivery_policy"), target_kind)
        except ValueError as exc:
            raise ValueError(str(exc)) from exc
        if build.get("delivery_policy_hash") != delivery_policy_hash(policy):
            raise ValueError("build.delivery_policy_hash 与实现深度合同不一致。")
        policy_source = "contract"
    else:
        policy = delivery_policy_for(target_kind)
        policy_source = "legacy-v2-derived"

    accepted_deltas = build.get("accepted_deltas", [])
    if not isinstance(accepted_deltas, list) or any(
        not isinstance(item, dict) for item in accepted_deltas
    ):
        raise ValueError("build.accepted_deltas 必须是对象数组。")

    acceptance = build.get("acceptance")
    if not isinstance(acceptance, dict):
        raise ValueError("build.acceptance 必须是对象。")
    final_checks = list(contract.final_checks)
    iteration_checks = list(contract.iteration_checks)
    if (
        contract_version >= 3
        and target_kind == "prototype"
        and "prototype-boundary" not in final_checks
    ):
        raise ValueError("prototype build 缺少不可跳过的 prototype-boundary 检查。")

    lane_name = "final" if lifecycle == "final_check" else "iteration"
    lane_checks = final_checks if lane_name == "final" else iteration_checks
    try:
        module = work_dir.relative_to(work_root).as_posix()
    except ValueError as exc:
        raise ValueError("active module 不在 build worktree 内。") from exc

    return {
        "id": str(meta.get("id") or work_dir.name),
        "name": str(meta.get("name") or work_dir.name),
        "module": module,
        "lifecycle_state": lifecycle,
        "contract_version": contract_version,
        "anchor": anchor,
        "target": {
            "kind": target_kind,
            "paths": target_paths,
            "entrypoints": target_entrypoints,
        },
        "approved_paths": target_paths,
        "approved_source_hash": approved_source_hash.strip(),
        "design_revision": design_revision,
        "delivery_policy": policy,
        "delivery_policy_source": policy_source,
        "accepted_deltas": accepted_deltas,
        "legacy_recovery": (
            currentness.get("legacy_recovery")
            if isinstance(currentness, dict)
            else None
        ),
        "acceptance_lane": {
            "name": lane_name,
            "checks": lane_checks,
            "iteration_checks": iteration_checks,
            "final_checks": final_checks,
        },
        "project": {
            "type": definition["project"]["type"],
            "implementation": definition["implementation"],
            "commands": definition["commands"],
            "web": definition["web"],
        },
    }


def _matches_selector(work_view: dict, selector: str) -> bool:
    meta = work_view.get("meta") or {}
    work_dir = Path(work_view.get("work_dir") or ".").resolve()
    normalized = selector.strip()
    if not normalized:
        return True
    resolved_selector = str(Path(normalized).expanduser().resolve())
    candidates = {
        str(meta.get("id") or ""),
        str(meta.get("name") or ""),
        str(work_view.get("work_dir") or ""),
        str(work_dir),
        work_dir.name,
    }
    return normalized in candidates or resolved_selector in candidates


def execution_context_payload(
    state: dict, *, module_selector: str | None = None
) -> tuple[dict, int]:
    candidates = []
    for work_view in state.get("active_work", []):
        meta = work_view.get("meta") or {}
        build = meta.get("build")
        if (
            isinstance(build, dict)
            and _lifecycle(meta) in ACTIVE_BUILD_LIFECYCLES
            and (module_selector is None or _matches_selector(work_view, module_selector))
        ):
            candidates.append(work_view)

    base = {"schema_version": 1, "route": "pmai-build"}
    if not candidates:
        return {**base, "status": "none", "active_builds": []}, 0
    if len(candidates) > 1:
        active_builds = [
            {
                "id": str((item.get("meta") or {}).get("id") or ""),
                "name": _work_display_name(item),
                "lifecycle_state": _lifecycle(item.get("meta") or {}),
            }
            for item in candidates
        ]
        return {
            **base,
            "status": "ambiguous",
            "reason": "存在多个可续接的 active build，必须先让 PM 指明模块。",
            "active_builds": active_builds,
        }, 0
    try:
        context = _build_execution_context(candidates[0])
    except ValueError as exc:
        meta = candidates[0].get("meta") or {}
        reason = str(exc)
        return {
            **base,
            "route": _blocking_route(candidates[0]),
            "status": "invalid",
            "reason": reason,
            "active_builds": [
                {
                    "id": str(meta.get("id") or ""),
                    "name": _work_display_name(candidates[0]),
                    "lifecycle_state": _lifecycle(meta),
                }
            ],
        }, 2
    return {**base, "status": "active", "active_builds": [context]}, 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "repo_root",
        nargs="?",
        default=None,
        help="Repository root (auto-detected if omitted)",
    )
    parser.add_argument(
        "--module",
        help="按模块目录、模块名或 work id 精确读取一个 active build",
    )
    args = parser.parse_args()
    repo_root = (
        Path(args.repo_root).expanduser().resolve()
        if args.repo_root
        else find_repo_root()
    )
    try:
        state = get_overall_state(repo_root, cwd=Path.cwd(), strict=True)
    except StateReadError as exc:
        print(
            json.dumps(
                {
                    "schema_version": 1,
                    "route": "pmai-build",
                    "status": "invalid",
                    "reason": str(exc),
                    "active_builds": [],
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        raise SystemExit(2) from exc

    payload, exit_code = execution_context_payload(state, module_selector=args.module)
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    if exit_code:
        raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
