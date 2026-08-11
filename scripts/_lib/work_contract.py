"""Canonical reader for module work lifecycle and build contracts.

Only this module understands historical ``stage``, duplicated lifecycle fields,
and the ``required_checks`` acceptance alias. Callers consume the normalized
view and writers emit the current contract shape directly.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping


CURRENT_BUILD_CONTRACT_VERSION = 5
VALID_LIFECYCLES = {
    "designing",
    "ready_to_build",
    "building",
    "iterating",
    "final_check",
    "landed",
    "documenting",
    "complete",
}
_BUILD_LIFECYCLES = {
    "building",
    "iterating",
    "final_check",
    "landed",
    "documenting",
    "complete",
}
_LIFECYCLE_STAGE = {
    "designing": 1,
    "ready_to_build": 1,
    "building": 2,
    "iterating": 2,
    "final_check": 3,
    "landed": 4,
    "documenting": 4,
    "complete": 4,
}


class WorkContractError(ValueError):
    """The persisted work contract cannot be normalized safely."""


@dataclass(frozen=True)
class WorkContract:
    lifecycle_state: str
    display_stage: int
    contract_version: int | None
    iteration_checks: tuple[str, ...]
    final_checks: tuple[str, ...]
    compatibility: tuple[str, ...]

    @property
    def is_legacy(self) -> bool:
        return bool(self.compatibility)

    def as_dict(self) -> dict[str, Any]:
        return {
            "lifecycle_state": self.lifecycle_state,
            "display_stage": self.display_stage,
            "contract_version": self.contract_version,
            "iteration_checks": list(self.iteration_checks),
            "final_checks": list(self.final_checks),
            "compatibility": list(self.compatibility),
            "is_legacy": self.is_legacy,
        }


def _version(build: Mapping[str, Any]) -> int:
    value = build.get("contract_version", 1)
    if isinstance(value, bool):
        raise WorkContractError("build.contract_version 必须是整数。")
    try:
        version = int(value)
    except (TypeError, ValueError) as exc:
        raise WorkContractError("build.contract_version 必须是整数。") from exc
    if version < 1 or version > CURRENT_BUILD_CONTRACT_VERSION:
        raise WorkContractError(
            f"build.contract_version={version} 不受支持；"
            f"当前最高版本为 {CURRENT_BUILD_CONTRACT_VERSION}。"
        )
    return version


def _lifecycle(value: Any, label: str) -> str:
    if not isinstance(value, str) or value not in VALID_LIFECYCLES:
        raise WorkContractError(f"{label} 不合法：{value!r}。")
    return value


def _stage(value: Any) -> int:
    if isinstance(value, bool):
        raise WorkContractError("stage 必须是正整数。")
    try:
        stage = int(value)
    except (TypeError, ValueError) as exc:
        raise WorkContractError("stage 必须是正整数。") from exc
    if stage < 1:
        raise WorkContractError("stage 必须是正整数。")
    return stage


def _stage_lifecycle(stage: int) -> str:
    if stage <= 1:
        return "designing"
    if stage == 2:
        return "building"
    if stage == 3:
        return "final_check"
    return "complete"


def _checks(value: Any, label: str, *, required: bool) -> tuple[str, ...]:
    if value is None and not required:
        return ()
    if not isinstance(value, list) or (required and not value):
        qualifier = "非空" if required else ""
        raise WorkContractError(f"{label} 必须是{qualifier}字符串数组。")
    if any(not isinstance(item, str) or not item.strip() for item in value):
        raise WorkContractError(f"{label} 必须只包含非空字符串。")
    normalized = tuple(item.strip() for item in value)
    if len(set(normalized)) != len(normalized):
        raise WorkContractError(f"{label} 不能包含重复检查。")
    return normalized


def normalize_work_contract(
    meta: Mapping[str, Any], *, _validate_acceptance: bool = True
) -> WorkContract:
    """Project persisted v1-v5 state into the current read model."""

    if not isinstance(meta, Mapping):
        raise WorkContractError(".work-meta.json 顶层必须是对象。")
    compatibility: list[str] = []
    raw_stage = meta.get("stage")
    display_stage = _stage(raw_stage) if raw_stage is not None else 0
    if raw_stage is not None:
        compatibility.append("stage")

    top_present = "lifecycle_state" in meta and meta.get("lifecycle_state") not in (None, "")
    top_lifecycle = (
        _lifecycle(meta.get("lifecycle_state"), "lifecycle_state") if top_present else ""
    )
    raw_build = meta.get("build")
    if raw_build is not None and not isinstance(raw_build, Mapping):
        raise WorkContractError("build 必须是对象。")

    if not isinstance(raw_build, Mapping):
        lifecycle = top_lifecycle
        if not lifecycle:
            if not display_stage:
                raise WorkContractError("模块状态缺少 lifecycle_state。")
            lifecycle = _stage_lifecycle(display_stage)
            compatibility.append("stage_lifecycle")
        return WorkContract(
            lifecycle_state=lifecycle,
            display_stage=display_stage or _LIFECYCLE_STAGE[lifecycle],
            contract_version=None,
            iteration_checks=(),
            final_checks=(),
            compatibility=tuple(compatibility),
        )

    version = _version(raw_build)
    if version < CURRENT_BUILD_CONTRACT_VERSION:
        compatibility.append(f"build_v{version}")
    build_present = (
        "lifecycle_state" in raw_build and raw_build.get("lifecycle_state") not in (None, "")
    )
    build_lifecycle = (
        _lifecycle(raw_build.get("lifecycle_state"), "build.lifecycle_state")
        if build_present
        else ""
    )
    if version >= CURRENT_BUILD_CONTRACT_VERSION:
        if top_present:
            raise WorkContractError("v5 build 只能在 build.lifecycle_state 保存生命周期。")
        if not build_lifecycle:
            raise WorkContractError("v5 build 缺少 build.lifecycle_state。")
        lifecycle = build_lifecycle
    else:
        if top_lifecycle and build_lifecycle and top_lifecycle != build_lifecycle:
            raise WorkContractError("顶层 lifecycle_state 与 build.lifecycle_state 不一致。")
        lifecycle = build_lifecycle or top_lifecycle
        if top_present:
            compatibility.append("top_level_build_lifecycle")
        if not lifecycle:
            if not display_stage:
                raise WorkContractError("旧 build 缺少可恢复的 lifecycle_state/stage。")
            lifecycle = _stage_lifecycle(display_stage)
            compatibility.append("stage_lifecycle")

    if lifecycle not in _BUILD_LIFECYCLES:
        raise WorkContractError(f"build 合同不能处于 {lifecycle} 状态。")
    if not _validate_acceptance:
        return WorkContract(
            lifecycle_state=lifecycle,
            display_stage=display_stage or _LIFECYCLE_STAGE[lifecycle],
            contract_version=version,
            iteration_checks=(),
            final_checks=(),
            compatibility=tuple(compatibility),
        )
    acceptance = raw_build.get("acceptance")
    if version >= 2 and not isinstance(acceptance, Mapping):
        raise WorkContractError("build.acceptance 必须是对象。")
    acceptance = acceptance if isinstance(acceptance, Mapping) else {}
    if version <= 3:
        final_checks = _checks(
            acceptance.get("required_checks"),
            "build.acceptance.required_checks",
            required=version >= 2,
        )
        iteration_checks = ()
        if "required_checks" in acceptance:
            compatibility.append("required_checks")
    elif version == 4:
        final_checks = _checks(
            acceptance.get("final_checks"),
            "build.acceptance.final_checks",
            required=True,
        )
        required_checks = _checks(
            acceptance.get("required_checks"),
            "build.acceptance.required_checks",
            required=True,
        )
        if final_checks != required_checks:
            raise WorkContractError(
                "build.acceptance.final_checks 与 required_checks 不一致。"
            )
        iteration_checks = _checks(
            acceptance.get("iteration_checks"),
            "build.acceptance.iteration_checks",
            required=False,
        )
        compatibility.append("required_checks")
    else:
        if "required_checks" in acceptance:
            raise WorkContractError("v5 acceptance 不再允许 required_checks。")
        final_checks = _checks(
            acceptance.get("final_checks"),
            "build.acceptance.final_checks",
            required=True,
        )
        iteration_checks = _checks(
            acceptance.get("iteration_checks"),
            "build.acceptance.iteration_checks",
            required=False,
        )

    return WorkContract(
        lifecycle_state=lifecycle,
        display_stage=display_stage or _LIFECYCLE_STAGE[lifecycle],
        contract_version=version,
        iteration_checks=iteration_checks,
        final_checks=final_checks,
        compatibility=tuple(compatibility),
    )


def normalize_work_state(meta: Mapping[str, Any]) -> WorkContract:
    """Normalize lifecycle/version/stage without requiring the acceptance body."""

    return normalize_work_contract(meta, _validate_acceptance=False)


def load_work_contract(path: Path) -> WorkContract:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise WorkContractError(f"文件不存在：{path}") from exc
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise WorkContractError(f"无法读取工作合同：{path}: {exc}") from exc
    return normalize_work_contract(value)


def main() -> int:
    parser = argparse.ArgumentParser(description="Normalize a PMAI work contract")
    parser.add_argument("meta_file", type=Path)
    args = parser.parse_args()
    try:
        contract = load_work_contract(args.meta_file)
    except WorkContractError as exc:
        raise SystemExit(str(exc)) from exc
    print(json.dumps(contract.as_dict(), ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
