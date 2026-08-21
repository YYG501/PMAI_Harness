#!/usr/bin/env python3
"""Manage PM decision-question authorization receipts in .work-meta.json."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from _lib.decision_gate import (
    DecisionGateError,
    answer_gate,
    cancel_gate,
    check_staged_authorization,
    consume_gate,
    context_summary,
    guard_pending_write,
    guard_authority_write,
    observe_answer,
    open_gate,
    parse_option,
    read_meta,
)


def emit(value: object) -> None:
    json.dump(value, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


def cmd_open(args: argparse.Namespace) -> None:
    item = open_gate(
        Path(args.module_dir),
        kind=args.kind,
        summary=args.summary,
        displayed_message=args.message,
        options=[parse_option(value) for value in args.option],
        allow_free_text=args.allow_free_text,
        session_id=args.session_id or os.environ.get("CODEX_THREAD_ID") or os.environ.get("CLAUDE_SESSION_ID"),
        display_message_id=args.display_message_id,
    )
    emit(item)


def cmd_observe(args: argparse.Namespace) -> None:
    emit(
        observe_answer(
            Path(args.repo_root).expanduser().resolve(),
            message=args.message,
            session_id=args.session_id,
            message_id=args.message_id,
            transcript_path=args.transcript_path,
        )
    )


def cmd_answer(args: argparse.Namespace) -> None:
    emit(answer_gate(Path(args.module_dir), gate_id=args.gate_id, event_id=args.event_id))


def cmd_consume(args: argparse.Namespace) -> None:
    emit(
        consume_gate(
            Path(args.module_dir), gate_id=args.gate_id, decision_ids=args.decision_id
        )
    )


def cmd_cancel(args: argparse.Namespace) -> None:
    emit(cancel_gate(Path(args.module_dir), gate_id=args.gate_id, reason=args.reason))


def cmd_status(args: argparse.Namespace) -> None:
    meta = read_meta(Path(args.module_dir))
    emit(context_summary(meta) or {"schema_version": 1, "items": [], "ready_authorization": None})


def cmd_guard_write(args: argparse.Namespace) -> None:
    emit(guard_authority_write(Path(args.module_dir)))


def cmd_guard_pending_write(args: argparse.Namespace) -> None:
    emit(guard_pending_write(Path(args.module_dir)))


def cmd_check_staged(args: argparse.Namespace) -> None:
    emit(check_staged_authorization(Path(args.repo_root).expanduser().resolve()))


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="cmd", required=True)

    open_parser = sub.add_parser("open", help="record one displayed pending question")
    open_parser.add_argument("module_dir")
    open_parser.add_argument("--kind", choices=["product-model", "project-definition", "one-way-door"], required=True)
    open_parser.add_argument("--summary", required=True)
    open_parser.add_argument("--message", required=True)
    open_parser.add_argument("--option", action="append", required=True, help="<id>=<label>")
    open_parser.add_argument("--allow-free-text", action="store_true")
    open_parser.add_argument("--session-id")
    open_parser.add_argument("--display-message-id")
    open_parser.set_defaults(func=cmd_open)

    observe = sub.add_parser("observe", help="bind a UserPromptSubmit event to the current pending gate")
    observe.add_argument("--repo-root", default=".")
    observe.add_argument("--message", required=True)
    observe.add_argument("--session-id")
    observe.add_argument("--message-id")
    observe.add_argument("--transcript-path")
    observe.set_defaults(func=cmd_observe)

    answer = sub.add_parser("answer", help="select one captured user message as this gate's answer")
    answer.add_argument("module_dir")
    answer.add_argument("--gate-id", required=True)
    answer.add_argument("--event-id", required=True)
    answer.set_defaults(func=cmd_answer)

    consume = sub.add_parser("consume", help="consume one answered gate into named decisions")
    consume.add_argument("module_dir")
    consume.add_argument("--gate-id", required=True)
    consume.add_argument("--decision-id", action="append", required=True)
    consume.set_defaults(func=cmd_consume)

    cancel = sub.add_parser("cancel", help="cancel a pending or answered gate without authorization")
    cancel.add_argument("module_dir")
    cancel.add_argument("--gate-id", required=True)
    cancel.add_argument("--reason", required=True)
    cancel.set_defaults(func=cmd_cancel)

    status = sub.add_parser("status", help="show the current module's gate receipts")
    status.add_argument("module_dir")
    status.set_defaults(func=cmd_status)

    guard = sub.add_parser("guard-authority-write", help="verify a current authorization window before decisions.md writes")
    guard.add_argument("module_dir")
    guard.set_defaults(func=cmd_guard_write)

    pending_guard = sub.add_parser("guard-pending-write", help="block design artifact writes while a displayed gate is unanswered")
    pending_guard.add_argument("module_dir")
    pending_guard.set_defaults(func=cmd_guard_pending_write)

    staged = sub.add_parser("check-staged", help="verify staged decision changes and all pending gates")
    staged.add_argument("--repo-root", default=".")
    staged.set_defaults(func=cmd_check_staged)
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        args.func(args)
    except DecisionGateError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
