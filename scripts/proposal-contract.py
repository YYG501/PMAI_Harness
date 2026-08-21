#!/usr/bin/env python3
"""Accept or validate the current PMAI Product Proposal contract."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from _lib.proposal import (
    ProposalContractError,
    accept_proposal,
    capture_intake_manifest,
    proposal_state,
    validate_current_proposal,
)
from _lib.decision_gate import DecisionGateError, guard_project_write


def _print(value: dict[str, object]) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2))


def cmd_accept(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).expanduser().resolve()
    project_gate_path = repo_root / ".pm-workflow" / "context" / "decision-gates.json"
    if project_gate_path.exists():
        try:
            guard_project_write(repo_root)
        except DecisionGateError as exc:
            raise ProposalContractError(str(exc)) from exc
    _print(
        accept_proposal(
            repo_root,
            proposal_id=args.proposal_id,
            proposal=args.proposal,
            supersedes=args.supersedes,
            accepted_at=args.accepted_at,
        )
    )
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    _print(validate_current_proposal(Path(args.repo_root)))
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    value = proposal_state(Path(args.repo_root))
    _print(value)
    return 2 if value["state"] == "invalid" else 0


def cmd_capture_intake(args: argparse.Namespace) -> int:
    _print(capture_intake_manifest(Path(args.repo_root)))
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subparsers = result.add_subparsers(dest="command", required=True)

    accept = subparsers.add_parser("accept", help="确认完整 Proposal 并更新当前版本合同")
    accept.add_argument("repo_root")
    accept.add_argument("--proposal", required=True, help="docs/proposals/ 下的版本化正文")
    accept.add_argument("--id", dest="proposal_id", required=True)
    accept.add_argument("--supersedes")
    accept.add_argument("--accepted-at", help="测试或迁移使用的 ISO-8601 时间")
    accept.set_defaults(func=cmd_accept)

    validate = subparsers.add_parser("validate", help="校验当前 Proposal 路径、哈希与交接摘要")
    validate.add_argument("repo_root")
    validate.set_defaults(func=cmd_validate)

    status = subparsers.add_parser("status", help="读取 Proposal gate 状态")
    status.add_argument("repo_root")
    status.set_defaults(func=cmd_status)

    capture = subparsers.add_parser(
        "capture-intake",
        help="在 PMAI 首次写入前固定已有仓内文件路径与 SHA-256",
    )
    capture.add_argument("repo_root")
    capture.set_defaults(func=cmd_capture_intake)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        return args.func(args)
    except ProposalContractError as exc:
        print(f"❌ {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
