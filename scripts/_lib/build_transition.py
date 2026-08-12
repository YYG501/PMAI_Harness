"""Pure mutations and guards for the persisted Build lifecycle."""

from __future__ import annotations

from typing import Callable

from .build_schema import (
    CURRENT_CONTRACT_VERSION,
    VALID_DOCS_STATUSES,
    contract_version,
    optional,
)


def set_build_lifecycle(meta: dict, build: dict, state: str) -> None:
    build["lifecycle_state"] = state
    if contract_version(build) >= CURRENT_CONTRACT_VERSION:
        meta.pop("lifecycle_state", None)
        meta.pop("stage", None)
    else:
        meta["lifecycle_state"] = state


def clear_review_ready(build: dict) -> None:
    acceptance = build.setdefault("acceptance", {})
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    acceptance["ready_at"] = None
    acceptance["ready_commit"] = None
    acceptance["ready_source_hash"] = None


def clear_finalization(build: dict) -> None:
    if contract_version(build) < 4:
        return
    build["finalization"] = {
        "requested_at": None,
        "requested_commit": None,
        "rebound_at": None,
    }


def validate_finalization_requested(build: dict) -> None:
    if contract_version(build) < 4:
        return
    finalization = build.get("finalization")
    if not isinstance(finalization, dict):
        raise SystemExit("build.finalization 必须是对象。")
    requested_at = optional(finalization.get("requested_at"))
    requested_commit = optional(finalization.get("requested_commit"))
    if not requested_at or not requested_commit:
        raise SystemExit(
            "PM 尚未请求定稿：快速迭代期间不能生成 review-ready 或运行完整 final checks。"
        )
    if requested_commit != optional(build.get("implementation_commit")):
        raise SystemExit(
            "定稿请求绑定的 implementation commit 已变化；先记录验收修复提交，"
            "由合同重新绑定后再运行 final checks。"
        )


def validate_review_ready(build: dict) -> None:
    acceptance = build.get("acceptance")
    if not isinstance(acceptance, dict):
        raise SystemExit("build.acceptance 必须是对象。")
    ready_at = optional(acceptance.get("ready_at"))
    ready_commit = optional(acceptance.get("ready_commit"))
    ready_source_hash = optional(acceptance.get("ready_source_hash"))
    if not ready_at or not ready_commit or not ready_source_hash:
        raise SystemExit(
            "当前实现尚未形成验收就绪快照：PM 请求定稿后，先对冻结提交完成全部 final checks，"
            "再运行 review-ready；final_check 不临时补实现或首次跑完整验收。"
        )
    if ready_commit != optional(build.get("implementation_commit")):
        raise SystemExit("验收就绪快照已过期：implementation commit 已变化，请回 build 重新检查。")
    if ready_source_hash != optional(build.get("approved_source_hash")):
        raise SystemExit("验收就绪快照已过期：approved source 已变化，请回 build 重新检查。")


def apply_transition(
    meta: dict,
    build: dict,
    *,
    state: str,
    current_state: str,
    valid_states: set[str],
    allowed_from: set[str] | None = None,
    docs_status: str | None = None,
    reason: str | None = None,
    timestamp: Callable[[], str],
) -> None:
    if state not in valid_states:
        raise SystemExit(f"未知 lifecycle state: {state}")
    if contract_version(build) < 2:
        raise SystemExit("显式 lifecycle transition 只适用于 build contract v2+。")
    if allowed_from is not None and current_state not in allowed_from:
        raise SystemExit(
            f"lifecycle 不能从 {current_state or '<empty>'} 进入 {state}；"
            f"允许来源：{', '.join(sorted(allowed_from))}。"
        )
    set_build_lifecycle(meta, build, state)
    if docs_status is not None:
        if docs_status not in VALID_DOCS_STATUSES:
            raise SystemExit(f"未知 docs status: {docs_status}")
        build["docs_status"] = docs_status
        build["docs_updated_at"] = timestamp()
    if reason:
        build["docs_failure_reason"] = reason
    elif docs_status == "complete":
        build.pop("docs_failure_reason", None)
