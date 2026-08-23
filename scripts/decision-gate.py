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
    answer_round,
    answer_project_gate,
    cancel_gate,
    cancel_project_gate,
    check_staged_authorization,
    consume_gate,
    consume_shared_understanding,
    consume_project_gate,
    confirm_shared_understanding,
    context_summary,
    guard_pending_write,
    guard_authority_write,
    guard_project_write,
    observe_answer,
    open_gate,
    open_round,
    open_shared_understanding,
    open_project_gate,
    parse_option,
    project_context_summary,
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


def cmd_open_project(args: argparse.Namespace) -> None:
    item = open_project_gate(
        Path(args.repo_root).expanduser().resolve(),
        kind=args.kind,
        summary=args.summary,
        displayed_message=args.message,
        options=[parse_option(value) for value in args.option],
        allow_free_text=args.allow_free_text,
        session_id=args.session_id or os.environ.get("CODEX_THREAD_ID") or os.environ.get("CLAUDE_SESSION_ID"),
        display_message_id=args.display_message_id,
    )
    emit(item)


def cmd_open_round(args: argparse.Namespace) -> None:
    questions = []
    for raw in args.question:
        try:
            value = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise DecisionGateError(f"--question 不是合法 JSON：{exc}") from exc
        if not isinstance(value, dict):
            raise DecisionGateError("--question 必须是 JSON 对象。")
        questions.append(value)
    emit(
        open_round(
            Path(args.module_dir),
            kind=args.kind,
            round_summary=args.round_summary,
            questions=questions,
            session_id=args.session_id or os.environ.get("CODEX_THREAD_ID") or os.environ.get("CLAUDE_SESSION_ID"),
            display_message_id=args.display_message_id,
        )
    )


def cmd_open_shared(args: argparse.Namespace) -> None:
    emit(
        open_shared_understanding(
            Path(args.module_dir),
            summary=args.summary,
            displayed_message=args.message,
            session_id=args.session_id or os.environ.get("CODEX_THREAD_ID") or os.environ.get("CLAUDE_SESSION_ID"),
            display_message_id=args.display_message_id,
        )
    )


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


def cmd_answer_project(args: argparse.Namespace) -> None:
    emit(
        answer_project_gate(
            Path(args.repo_root).expanduser().resolve(),
            gate_id=args.gate_id,
            event_id=args.event_id,
        )
    )


def cmd_answer_round(args: argparse.Namespace) -> None:
    selections = {}
    for raw in args.selection:
        if "=" not in raw:
            raise DecisionGateError("--selection 必须使用 gate-id=option-id 格式。")
        gate_id, option_id = raw.split("=", 1)
        if not gate_id.strip() or not option_id.strip():
            raise DecisionGateError("--selection 的 gate-id 和 option-id 不能为空。")
        if gate_id.strip() in selections:
            raise DecisionGateError("--selection 不能重复指定同一 gate-id。")
        selections[gate_id.strip()] = option_id.strip()
    free_texts = {}
    for raw in args.free_text:
        if "=" not in raw:
            raise DecisionGateError("--free-text 必须使用 gate-id=answer 格式。")
        gate_id, answer = raw.split("=", 1)
        if not gate_id.strip() or not answer.strip():
            raise DecisionGateError("--free-text 的 gate-id 和回答不能为空。")
        if gate_id.strip() in free_texts:
            raise DecisionGateError("--free-text 不能重复指定同一 gate-id。")
        free_texts[gate_id.strip()] = answer.strip()
    emit(
        answer_round(
            Path(args.module_dir),
            event_id=args.event_id,
            selections=selections,
            free_texts=free_texts,
        )
    )


def cmd_confirm_shared(args: argparse.Namespace) -> None:
    emit(
        confirm_shared_understanding(
            Path(args.module_dir), gate_id=args.gate_id, event_id=args.event_id
        )
    )


def cmd_consume(args: argparse.Namespace) -> None:
    emit(
        consume_gate(
            Path(args.module_dir), gate_id=args.gate_id, decision_ids=args.decision_id
        )
    )


def cmd_consume_shared(args: argparse.Namespace) -> None:
    emit(consume_shared_understanding(Path(args.module_dir), gate_id=args.gate_id))


def cmd_consume_project(args: argparse.Namespace) -> None:
    emit(
        consume_project_gate(
            Path(args.repo_root).expanduser().resolve(),
            gate_id=args.gate_id,
            artifact=args.artifact,
        )
    )


def cmd_cancel(args: argparse.Namespace) -> None:
    emit(cancel_gate(Path(args.module_dir), gate_id=args.gate_id, reason=args.reason))


def cmd_cancel_project(args: argparse.Namespace) -> None:
    emit(
        cancel_project_gate(
            Path(args.repo_root).expanduser().resolve(),
            gate_id=args.gate_id,
            reason=args.reason,
        )
    )


def cmd_status(args: argparse.Namespace) -> None:
    meta = read_meta(Path(args.module_dir))
    emit(context_summary(meta) or {"schema_version": 1, "items": [], "ready_authorization": None})


def cmd_status_project(args: argparse.Namespace) -> None:
    emit(project_context_summary(Path(args.repo_root).expanduser().resolve()))


def cmd_guard_write(args: argparse.Namespace) -> None:
    emit(guard_authority_write(Path(args.module_dir)))


def cmd_guard_pending_write(args: argparse.Namespace) -> None:
    emit(guard_pending_write(Path(args.module_dir), artifact=args.artifact))


def cmd_guard_project_write(args: argparse.Namespace) -> None:
    emit(guard_project_write(Path(args.repo_root).expanduser().resolve()))


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

    open_project = sub.add_parser("open-project", help="record one displayed project/stage question")
    open_project.add_argument("repo_root")
    open_project.add_argument("--kind", choices=["product-model", "project-definition", "one-way-door"], required=True)
    open_project.add_argument("--summary", required=True)
    open_project.add_argument("--message", required=True)
    open_project.add_argument("--option", action="append", required=True, help="<id>=<label>")
    open_project.add_argument("--allow-free-text", action="store_true")
    open_project.add_argument("--session-id")
    open_project.add_argument("--display-message-id")
    open_project.set_defaults(func=cmd_open_project)

    open_round = sub.add_parser("open-round", help="record one Design frontier round")
    open_round.add_argument("module_dir")
    open_round.add_argument("--kind", choices=["product-model", "project-definition", "one-way-door"], required=True)
    open_round.add_argument("--round-summary", required=True)
    open_round.add_argument("--question", action="append", required=True, help="question JSON object")
    open_round.add_argument("--session-id")
    open_round.add_argument("--display-message-id")
    open_round.set_defaults(func=cmd_open_round)

    open_shared = sub.add_parser(
        "open-shared", help="record Grill's final shared-understanding confirmation"
    )
    open_shared.add_argument("module_dir")
    open_shared.add_argument("--summary", required=True)
    open_shared.add_argument("--message", required=True)
    open_shared.add_argument("--session-id")
    open_shared.add_argument("--display-message-id")
    open_shared.set_defaults(func=cmd_open_shared)

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

    answer_project = sub.add_parser("answer-project", help="select a captured user message as a project gate answer")
    answer_project.add_argument("repo_root")
    answer_project.add_argument("--gate-id", required=True)
    answer_project.add_argument("--event-id", required=True)
    answer_project.set_defaults(func=cmd_answer_project)

    answer_round = sub.add_parser("answer-round", help="answer one or more questions in a frontier round")
    answer_round.add_argument("module_dir")
    answer_round.add_argument("--event-id", required=True)
    answer_round.add_argument("--selection", action="append", default=[], help="<gate-id>=<option-id>")
    answer_round.add_argument("--free-text", action="append", default=[], help="<gate-id>=<answer>")
    answer_round.set_defaults(func=cmd_answer_round)

    confirm_shared = sub.add_parser(
        "confirm-shared", help="confirm a displayed shared-understanding summary"
    )
    confirm_shared.add_argument("module_dir")
    confirm_shared.add_argument("--gate-id", required=True)
    confirm_shared.add_argument("--event-id", required=True)
    confirm_shared.set_defaults(func=cmd_confirm_shared)

    consume = sub.add_parser("consume", help="consume one answered gate into named decisions")
    consume.add_argument("module_dir")
    consume.add_argument("--gate-id", required=True)
    consume.add_argument("--decision-id", action="append", required=True)
    consume.set_defaults(func=cmd_consume)

    consume_shared = sub.add_parser(
        "consume-shared", help="consume the shared-understanding receipt"
    )
    consume_shared.add_argument("module_dir")
    consume_shared.add_argument("--gate-id", required=True)
    consume_shared.set_defaults(func=cmd_consume_shared)

    consume_project = sub.add_parser("consume-project", help="consume a project gate into a named workflow action")
    consume_project.add_argument("repo_root")
    consume_project.add_argument("--gate-id", required=True)
    consume_project.add_argument("--artifact", required=True, help="workflow action or artifact authorization id")
    consume_project.set_defaults(func=cmd_consume_project)

    cancel = sub.add_parser("cancel", help="cancel a pending or answered gate without authorization")
    cancel.add_argument("module_dir")
    cancel.add_argument("--gate-id", required=True)
    cancel.add_argument("--reason", required=True)
    cancel.set_defaults(func=cmd_cancel)

    cancel_project = sub.add_parser("cancel-project", help="cancel a project/stage gate")
    cancel_project.add_argument("repo_root")
    cancel_project.add_argument("--gate-id", required=True)
    cancel_project.add_argument("--reason", required=True)
    cancel_project.set_defaults(func=cmd_cancel_project)

    status = sub.add_parser("status", help="show the current module's gate receipts")
    status.add_argument("module_dir")
    status.set_defaults(func=cmd_status)

    status_project = sub.add_parser("status-project", help="show project/stage gate receipts")
    status_project.add_argument("repo_root")
    status_project.set_defaults(func=cmd_status_project)

    guard = sub.add_parser("guard-authority-write", help="verify a current authorization window before decisions.md writes")
    guard.add_argument("module_dir")
    guard.set_defaults(func=cmd_guard_write)

    pending_guard = sub.add_parser("guard-pending-write", help="block design artifact writes while a displayed gate is unanswered")
    pending_guard.add_argument("module_dir")
    pending_guard.add_argument("--artifact", choices=["discussion", "spec"])
    pending_guard.set_defaults(func=cmd_guard_pending_write)

    project_guard = sub.add_parser("guard-project-write", help="verify an answered project gate before Proposal writes")
    project_guard.add_argument("repo_root")
    project_guard.set_defaults(func=cmd_guard_project_write)

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
