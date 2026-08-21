"""Machine-verifiable PM answer binding for module design decisions.

Decision gates live inside the active module's ``.work-meta.json``.  They are
authorization receipts, not a second product-decision source: ``decisions.md``
continues to own the decision itself while this module proves which displayed
question and user message authorized it.
"""

from __future__ import annotations

import hashlib
import json
import re
import secrets
import subprocess
from copy import deepcopy
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
VALID_GATE_STATUSES = {"pending", "answered", "consumed", "cancelled"}
VALID_GATE_KINDS = {"product-model", "project-definition", "one-way-door"}
DECISION_ID_RE = re.compile(r"^D[0-9]+$", re.IGNORECASE)
DECISION_HEADING_RE = re.compile(r"^#{2,6}\s+(D[0-9]+)\b.*$", re.IGNORECASE)
SHORT_ANSWER_LIMIT = 2048


class DecisionGateError(ValueError):
    """Raised when an authorization receipt is missing, stale, or ambiguous."""


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _require_string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise DecisionGateError(f"{label} 必须是非空字符串。")
    return value.strip()


def _git(repo_root: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if check and result.returncode != 0:
        raise DecisionGateError(result.stderr.strip() or "无法读取 Git 授权依据。")
    return result


def git_head(repo_root: Path) -> str:
    return _require_string(_git(repo_root, "rev-parse", "HEAD").stdout, "Git HEAD")


def repo_root_for(module_dir: Path) -> Path:
    resolved = module_dir.expanduser().resolve()
    result = subprocess.run(
        ["git", "-C", str(resolved), "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise DecisionGateError(f"无法定位模块所属 Git 仓库：{module_dir}")
    return Path(result.stdout.strip()).resolve()


def module_relative(repo_root: Path, module_dir: Path) -> str:
    try:
        return module_dir.expanduser().resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError as exc:
        raise DecisionGateError(f"模块目录不在仓库内：{module_dir}") from exc


def meta_path(module_dir: Path) -> Path:
    return module_dir / ".work-meta.json"


def read_meta(module_dir: Path) -> dict[str, Any]:
    path = meta_path(module_dir)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise DecisionGateError(f"缺少模块工作状态：{path}") from exc
    except json.JSONDecodeError as exc:
        raise DecisionGateError(f".work-meta.json 不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DecisionGateError(".work-meta.json 顶层必须是对象。")
    return value


def write_meta(module_dir: Path, meta: dict[str, Any]) -> None:
    path = meta_path(module_dir)
    tmp = path.with_name(f".{path.name}.decision-gate.tmp")
    tmp.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def new_contract(baseline_commit: str) -> dict[str, Any]:
    return {
        "schema_version": SCHEMA_VERSION,
        "design_base_commit": _require_string(baseline_commit, "design_base_commit"),
        "items": [],
        "ready_authorization": None,
    }


def ensure_contract(
    meta: dict[str, Any], *, baseline_commit: str, reset_baseline: bool = False
) -> dict[str, Any]:
    raw = meta.get("decision_gates")
    if raw is None:
        raw = new_contract(baseline_commit)
        meta["decision_gates"] = raw
    contract = validate_contract(raw, work_id=str(meta.get("id") or ""))
    if reset_baseline:
        if any(item["status"] in {"pending", "answered"} for item in contract["items"]):
            raise DecisionGateError("仍有未消费的 PM 决策题，不能重置 design 授权基线。")
        contract["design_base_commit"] = _require_string(
            baseline_commit, "design_base_commit"
        )
        contract["ready_authorization"] = None
        meta["decision_gates"] = contract
    return contract


def _validate_options(value: Any, label: str) -> list[dict[str, str]]:
    if not isinstance(value, list) or not value:
        raise DecisionGateError(f"{label} 必须是非空选项数组。")
    result: list[dict[str, str]] = []
    seen: set[str] = set()
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            raise DecisionGateError(f"{label}[{index}] 必须是对象。")
        option_id = _require_string(item.get("id"), f"{label}[{index}].id")
        option_label = _require_string(item.get("label"), f"{label}[{index}].label")
        if option_id in seen:
            raise DecisionGateError(f"{label} 存在重复选项 ID：{option_id}")
        seen.add(option_id)
        result.append({"id": option_id, "label": option_label})
    return result


def _validate_answer_event(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise DecisionGateError(f"{label} 必须是对象。")
    event = {
        "event_id": _require_string(value.get("event_id"), f"{label}.event_id"),
        "session_id": str(value.get("session_id") or "").strip() or None,
        "message_id": str(value.get("message_id") or "").strip() or None,
        "message": _require_string(value.get("message"), f"{label}.message"),
        "message_sha256": _require_string(
            value.get("message_sha256"), f"{label}.message_sha256"
        ),
        "observed_at": _require_string(value.get("observed_at"), f"{label}.observed_at"),
        "source": _require_string(value.get("source"), f"{label}.source"),
    }
    if sha256_text(event["message"]) != event["message_sha256"]:
        raise DecisionGateError(f"{label} 的 message hash 不匹配。")
    return event


def validate_contract(value: Any, *, work_id: str = "") -> dict[str, Any]:
    if not isinstance(value, dict):
        raise DecisionGateError("decision_gates 必须是对象。")
    if value.get("schema_version") != SCHEMA_VERSION:
        raise DecisionGateError(
            f"decision_gates.schema_version 必须为 {SCHEMA_VERSION}。"
        )
    baseline = _require_string(value.get("design_base_commit"), "decision_gates.design_base_commit")
    items = value.get("items")
    if not isinstance(items, list):
        raise DecisionGateError("decision_gates.items 必须是数组。")

    normalized_items: list[dict[str, Any]] = []
    gate_ids: set[str] = set()
    question_ids: set[str] = set()
    answer_event_owners: dict[str, str] = {}
    unresolved = 0
    for index, raw in enumerate(items):
        label = f"decision_gates.items[{index}]"
        if not isinstance(raw, dict):
            raise DecisionGateError(f"{label} 必须是对象。")
        gate_id = _require_string(raw.get("gate_id"), f"{label}.gate_id")
        question_id = _require_string(raw.get("question_id"), f"{label}.question_id")
        if gate_id in gate_ids or question_id in question_ids:
            raise DecisionGateError("decision_gates 存在重复 gate_id 或 question_id。")
        gate_ids.add(gate_id)
        question_ids.add(question_id)
        item_work_id = _require_string(raw.get("work_id"), f"{label}.work_id")
        if work_id and item_work_id != work_id:
            raise DecisionGateError(f"{label}.work_id 与当前工作不一致。")
        kind = _require_string(raw.get("kind"), f"{label}.kind")
        if kind not in VALID_GATE_KINDS:
            raise DecisionGateError(f"{label}.kind 不受支持：{kind}")
        status = _require_string(raw.get("status"), f"{label}.status")
        if status not in VALID_GATE_STATUSES:
            raise DecisionGateError(f"{label}.status 不合法：{status}")
        if status in {"pending", "answered"}:
            unresolved += 1

        question = raw.get("question")
        if not isinstance(question, dict):
            raise DecisionGateError(f"{label}.question 必须是对象。")
        normalized_question = {
            "summary": _require_string(question.get("summary"), f"{label}.question.summary"),
            "displayed_message": _require_string(
                question.get("displayed_message"), f"{label}.question.displayed_message"
            ),
            "displayed_message_sha256": _require_string(
                question.get("displayed_message_sha256"),
                f"{label}.question.displayed_message_sha256",
            ),
            "displayed_at": _require_string(
                question.get("displayed_at"), f"{label}.question.displayed_at"
            ),
            "display_session_id": str(question.get("display_session_id") or "").strip()
            or None,
            "display_message_id": str(question.get("display_message_id") or "").strip()
            or None,
            "options": _validate_options(question.get("options"), f"{label}.question.options"),
            "allow_free_text": question.get("allow_free_text") is True,
        }
        if (
            sha256_text(normalized_question["displayed_message"])
            != normalized_question["displayed_message_sha256"]
        ):
            raise DecisionGateError(f"{label} 的展示消息 hash 不匹配。")

        raw_candidates = raw.get("answer_candidates", [])
        if not isinstance(raw_candidates, list):
            raise DecisionGateError(f"{label}.answer_candidates 必须是数组。")
        candidates = [
            _validate_answer_event(candidate, f"{label}.answer_candidates[{candidate_index}]")
            for candidate_index, candidate in enumerate(raw_candidates)
        ]
        candidate_ids = {candidate["event_id"] for candidate in candidates}
        if len(candidate_ids) != len(candidates):
            raise DecisionGateError(f"{label} 存在重复 answer candidate。")
        for event_id in candidate_ids:
            owner = answer_event_owners.setdefault(event_id, gate_id)
            if owner != gate_id:
                raise DecisionGateError("同一用户答复事件被绑定到多个 decision gate。")

        answer = raw.get("answer")
        normalized_answer = None
        if answer is not None:
            if not isinstance(answer, dict):
                raise DecisionGateError(f"{label}.answer 必须是对象。")
            event = _validate_answer_event(answer.get("event"), f"{label}.answer.event")
            if event["event_id"] not in candidate_ids:
                raise DecisionGateError(f"{label}.answer 必须来自本 gate 已捕获的用户消息。")
            normalized_answer = {
                "event": event,
                "selected_option_id": str(answer.get("selected_option_id") or "").strip()
                or None,
                "answered_at": _require_string(
                    answer.get("answered_at"), f"{label}.answer.answered_at"
                ),
            }

        decision_ids = raw.get("authorized_decision_ids", [])
        if not isinstance(decision_ids, list):
            raise DecisionGateError(f"{label}.authorized_decision_ids 必须是数组。")
        normalized_ids: list[str] = []
        for raw_id in decision_ids:
            decision_id = _require_string(raw_id, f"{label}.authorized_decision_ids").upper()
            if not DECISION_ID_RE.fullmatch(decision_id):
                raise DecisionGateError(f"决定 ID 不合法：{decision_id}")
            if decision_id not in normalized_ids:
                normalized_ids.append(decision_id)

        consumed_by = raw.get("consumed_by")
        if consumed_by is not None:
            if not isinstance(consumed_by, dict):
                raise DecisionGateError(f"{label}.consumed_by 必须是对象。")
            decision_hashes = consumed_by.get("decision_hashes")
            if not isinstance(decision_hashes, dict):
                raise DecisionGateError(f"{label}.consumed_by.decision_hashes 必须是对象。")
            normalized_hashes: dict[str, str] = {}
            for raw_id, raw_hash in decision_hashes.items():
                decision_id = _require_string(raw_id, f"{label}.consumed_by.decision_hashes key").upper()
                digest = _require_string(raw_hash, f"{label}.consumed_by.decision_hashes[{decision_id}]")
                if not DECISION_ID_RE.fullmatch(decision_id) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                    raise DecisionGateError(f"{label}.consumed_by.decision_hashes 不合法。")
                normalized_hashes[decision_id] = digest
            consumed_by = {
                "checkpoint_commit": _require_string(
                    consumed_by.get("checkpoint_commit"),
                    f"{label}.consumed_by.checkpoint_commit",
                ),
                "decision_hashes": normalized_hashes,
                "bound_at": _require_string(
                    consumed_by.get("bound_at"), f"{label}.consumed_by.bound_at"
                ),
            }

        if status == "pending" and normalized_answer is not None:
            raise DecisionGateError(f"{label} pending 时不能已有 answer。")
        if status in {"answered", "consumed"} and normalized_answer is None:
            raise DecisionGateError(f"{label} {status} 时必须有 answer。")
        if status == "consumed" and not normalized_ids:
            raise DecisionGateError(f"{label} consumed 时必须绑定决定 ID。")
        if status == "consumed" and not str(raw.get("consumed_at") or "").strip():
            raise DecisionGateError(f"{label} consumed 时必须记录 consumed_at。")
        if status != "consumed" and (normalized_ids or consumed_by is not None):
            raise DecisionGateError(f"{label} 未 consumed 时不能绑定决定或 checkpoint。")

        normalized_items.append(
            {
                "gate_id": gate_id,
                "question_id": question_id,
                "work_id": item_work_id,
                "kind": kind,
                "status": status,
                "question": normalized_question,
                "answer_candidates": candidates,
                "answer": normalized_answer,
                "authorized_decision_ids": normalized_ids,
                "consumed_at": str(raw.get("consumed_at") or "").strip() or None,
                "consumed_by": consumed_by,
                "cancelled_at": str(raw.get("cancelled_at") or "").strip() or None,
                "cancel_reason": str(raw.get("cancel_reason") or "").strip() or None,
            }
        )

    if unresolved > 1:
        raise DecisionGateError("同一工作同时存在多个未消费 decision gate。")
    ready_authorization = value.get("ready_authorization")
    if ready_authorization is not None and not isinstance(ready_authorization, dict):
        raise DecisionGateError("decision_gates.ready_authorization 必须是对象或 null。")
    return {
        "schema_version": SCHEMA_VERSION,
        "design_base_commit": baseline,
        "items": normalized_items,
        "ready_authorization": deepcopy(ready_authorization),
    }


def parse_option(raw: str) -> dict[str, str]:
    if "=" not in raw:
        raise DecisionGateError("选项必须使用 <id>=<label> 格式。")
    option_id, label = raw.split("=", 1)
    return {"id": _require_string(option_id, "option id"), "label": _require_string(label, "option label")}


def open_gate(
    module_dir: Path,
    *,
    kind: str,
    summary: str,
    displayed_message: str,
    options: list[dict[str, str]],
    allow_free_text: bool,
    session_id: str | None,
    display_message_id: str | None,
) -> dict[str, Any]:
    meta = read_meta(module_dir)
    if str(meta.get("lifecycle_state") or "") != "designing":
        raise DecisionGateError("只有 designing 工作可以打开产品决定授权题。")
    repo_root = repo_root_for(module_dir)
    contract = ensure_contract(meta, baseline_commit=git_head(repo_root))
    if any(item["status"] in {"pending", "answered"} for item in contract["items"]):
        raise DecisionGateError("当前工作已有一题等待答复或消费，不能同时打开下一题。")
    if kind not in VALID_GATE_KINDS:
        raise DecisionGateError(f"不支持的 decision gate kind：{kind}")
    stamp = now_iso()
    entropy = sha256_text(
        "\n".join([str(meta.get("id") or ""), summary, displayed_message, stamp])
    )[:12]
    gate_id = f"gate-{entropy}"
    question_id = f"question-{entropy}"
    item = {
        "gate_id": gate_id,
        "question_id": question_id,
        "work_id": _require_string(meta.get("id"), "work id"),
        "kind": kind,
        "status": "pending",
        "question": {
            "summary": _require_string(summary, "question summary"),
            "displayed_message": _require_string(displayed_message, "displayed message"),
            "displayed_message_sha256": sha256_text(displayed_message.strip()),
            "displayed_at": stamp,
            "display_session_id": (session_id or "").strip() or None,
            "display_message_id": (display_message_id or "").strip() or None,
            "options": _validate_options(options, "question.options"),
            "allow_free_text": bool(allow_free_text),
        },
        "answer_candidates": [],
        "answer": None,
        "authorized_decision_ids": [],
        "consumed_at": None,
        "consumed_by": None,
        "cancelled_at": None,
        "cancel_reason": None,
    }
    contract["items"].append(item)
    contract["ready_authorization"] = None
    meta["decision_gates"] = validate_contract(contract, work_id=item["work_id"])
    write_meta(module_dir, meta)
    return item


def _active_meta_paths(repo_root: Path) -> list[Path]:
    modules = repo_root / "docs" / "modules"
    if not modules.is_dir():
        return []
    result: list[Path] = []
    for path in sorted(modules.glob("*/.work-meta.json")):
        try:
            path.resolve().relative_to(repo_root.resolve())
        except ValueError:
            continue
        if path.is_file() and not path.is_symlink():
            result.append(path)
    return result


def _event_id(
    *, session_id: str | None, message_id: str | None, transcript_path: str | None, message: str
) -> str:
    if message_id:
        stable = [session_id or "", message_id, transcript_path or "", message]
    else:
        # Claude/Codex hook payloads do not always expose a host message ID.
        # A fresh nonce keeps two legitimate replies such as sequential "1"
        # answers distinct instead of treating their equal text as one event.
        stable = [session_id or "", transcript_path or "", message, secrets.token_hex(16)]
    return "answer-" + sha256_text("\n".join(stable))[:24]


def observe_answer(
    repo_root: Path,
    *,
    message: str,
    session_id: str | None,
    message_id: str | None,
    transcript_path: str | None,
) -> dict[str, Any]:
    answer_text = message.strip()
    if not answer_text or len(answer_text) > SHORT_ANSWER_LIMIT:
        return {"status": "none", "reason": "用户消息不是可捕获的短答复。"}

    candidates: list[tuple[Path, dict[str, Any], dict[str, Any], dict[str, Any]]] = []
    all_events: dict[str, str] = {}
    for path in _active_meta_paths(repo_root):
        module_dir = path.parent
        meta = read_meta(module_dir)
        raw_contract = meta.get("decision_gates")
        if raw_contract is None:
            continue
        contract = validate_contract(raw_contract, work_id=str(meta.get("id") or ""))
        for item in contract["items"]:
            for event in item["answer_candidates"]:
                all_events[event["event_id"]] = item["gate_id"]
            if item["status"] != "pending":
                continue
            display_session = item["question"].get("display_session_id")
            if display_session and display_session != session_id:
                continue
            candidates.append((module_dir, meta, contract, item))

    if not candidates:
        return {"status": "none", "reason": "当前没有已展示且 pending 的 decision gate。"}
    if len(candidates) != 1:
        return {
            "status": "ambiguous",
            "reason": "当前消息可能对应多个 pending decision gate，未绑定任何问题。",
            "gate_ids": [item[3]["gate_id"] for item in candidates],
        }

    module_dir, meta, contract, item = candidates[0]
    event_id = _event_id(
        session_id=session_id,
        message_id=message_id,
        transcript_path=transcript_path,
        message=answer_text,
    )
    owner = all_events.get(event_id)
    if owner and owner != item["gate_id"]:
        raise DecisionGateError("同一用户答复事件已经属于另一个 decision gate。")
    existing = next(
        (event for event in item["answer_candidates"] if event["event_id"] == event_id), None
    )
    if existing is None:
        event = {
            "event_id": event_id,
            "session_id": (session_id or "").strip() or None,
            "message_id": (message_id or "").strip() or None,
            "message": answer_text,
            "message_sha256": sha256_text(answer_text),
            "observed_at": now_iso(),
            "source": "user_prompt_submit",
        }
        for target in contract["items"]:
            if target["gate_id"] == item["gate_id"]:
                target["answer_candidates"].append(event)
                break
        meta["decision_gates"] = validate_contract(
            contract, work_id=str(meta.get("id") or "")
        )
        write_meta(module_dir, meta)
    return {
        "status": "observed",
        "module": module_relative(repo_root, module_dir),
        "gate_id": item["gate_id"],
        "question_id": item["question_id"],
        "event_id": event_id,
        "question_summary": item["question"]["summary"],
    }


def _find_gate(contract: dict[str, Any], gate_id: str) -> dict[str, Any]:
    for item in contract["items"]:
        if item["gate_id"] == gate_id:
            return item
    raise DecisionGateError(f"找不到 decision gate：{gate_id}")


def answer_gate(module_dir: Path, *, gate_id: str, event_id: str) -> dict[str, Any]:
    meta = read_meta(module_dir)
    contract = validate_contract(meta.get("decision_gates"), work_id=str(meta.get("id") or ""))
    item = _find_gate(contract, gate_id)
    if item["status"] != "pending":
        raise DecisionGateError(f"decision gate 当前为 {item['status']}，不能重复回答。")
    event = next(
        (candidate for candidate in item["answer_candidates"] if candidate["event_id"] == event_id),
        None,
    )
    if event is None:
        raise DecisionGateError("该用户消息不是在本题 pending 时捕获的答复。")
    display_session = item["question"].get("display_session_id")
    if display_session and event.get("session_id") != display_session:
        raise DecisionGateError("用户答复事件与问题展示 session 不一致。")
    answer_text = event["message"].strip()
    option_by_id = {option["id"]: option for option in item["question"]["options"]}
    option_by_label = {option["label"]: option for option in item["question"]["options"]}
    selected = option_by_id.get(answer_text) or option_by_label.get(answer_text)
    if selected is None and re.fullmatch(r"[0-9]+", answer_text):
        raise DecisionGateError("数字答复不属于本题展示的任何选项。")
    if selected is None and not item["question"]["allow_free_text"]:
        raise DecisionGateError("答复没有匹配本题选项；请让 PM 重新回答当前问题。")
    item["status"] = "answered"
    item["answer"] = {
        "event": event,
        "selected_option_id": selected["id"] if selected else None,
        "answered_at": now_iso(),
    }
    meta["decision_gates"] = validate_contract(contract, work_id=str(meta.get("id") or ""))
    write_meta(module_dir, meta)
    return item


def consume_gate(
    module_dir: Path, *, gate_id: str, decision_ids: Iterable[str]
) -> dict[str, Any]:
    meta = read_meta(module_dir)
    contract = validate_contract(meta.get("decision_gates"), work_id=str(meta.get("id") or ""))
    item = _find_gate(contract, gate_id)
    if item["status"] != "answered":
        raise DecisionGateError(f"decision gate 当前为 {item['status']}，不能消费。")
    normalized: list[str] = []
    for raw in decision_ids:
        decision_id = _require_string(raw, "decision id").upper()
        if not DECISION_ID_RE.fullmatch(decision_id):
            raise DecisionGateError(f"决定 ID 不合法：{decision_id}")
        if decision_id not in normalized:
            normalized.append(decision_id)
    if not normalized:
        raise DecisionGateError("consume 必须绑定至少一个决定 ID。")
    already_owned = {
        decision_id: other["gate_id"]
        for other in contract["items"]
        if other["status"] == "consumed"
        for decision_id in other["authorized_decision_ids"]
    }
    conflicts = [decision_id for decision_id in normalized if decision_id in already_owned]
    if conflicts:
        raise DecisionGateError(
            "决定 ID 已由其它答复消费：" + "、".join(sorted(conflicts))
        )
    item["status"] = "consumed"
    item["authorized_decision_ids"] = normalized
    item["consumed_at"] = now_iso()
    item["consumed_by"] = None
    contract["ready_authorization"] = None
    meta["decision_gates"] = validate_contract(contract, work_id=str(meta.get("id") or ""))
    write_meta(module_dir, meta)
    return item


def cancel_gate(module_dir: Path, *, gate_id: str, reason: str) -> dict[str, Any]:
    meta = read_meta(module_dir)
    contract = validate_contract(meta.get("decision_gates"), work_id=str(meta.get("id") or ""))
    item = _find_gate(contract, gate_id)
    if item["status"] not in {"pending", "answered"}:
        raise DecisionGateError(f"decision gate 当前为 {item['status']}，不能取消。")
    item["status"] = "cancelled"
    item["cancelled_at"] = now_iso()
    item["cancel_reason"] = _require_string(reason, "cancel reason")
    item["answer"] = None
    meta["decision_gates"] = validate_contract(contract, work_id=str(meta.get("id") or ""))
    write_meta(module_dir, meta)
    return item


def parse_decision_sections(text: str) -> dict[str, str]:
    sections: dict[str, list[str]] = {}
    current: str | None = None
    current_level = 0
    for line in text.splitlines():
        match = DECISION_HEADING_RE.match(line.strip())
        if match:
            current = match.group(1).upper()
            current_level = len(line.lstrip()) - len(line.lstrip("#"))
            sections[current] = [line.rstrip()]
            continue
        heading = re.match(r"^(#{1,6})\s+", line.strip())
        if heading and current is not None and len(heading.group(1)) <= current_level:
            current = None
            current_level = 0
        elif current is not None:
            sections[current].append(line.rstrip())
    return {
        decision_id: "\n".join(lines).strip() + "\n"
        for decision_id, lines in sections.items()
    }


def _git_file(repo_root: Path, ref: str, relative: str) -> str:
    result = _git(repo_root, "show", f"{ref}:{relative}", check=False)
    if result.returncode == 0:
        return result.stdout
    stderr = result.stderr.lower()
    if "does not exist" in stderr or "exists on disk" in stderr or "path" in stderr:
        return ""
    raise DecisionGateError(result.stderr.strip() or f"无法读取 {ref}:{relative}")


def decision_sections_at(repo_root: Path, ref: str, module_rel: str) -> dict[str, str]:
    return parse_decision_sections(_git_file(repo_root, ref, f"{module_rel}/decisions.md"))


def changed_decision_ids(
    repo_root: Path, *, before_ref: str, after_ref: str, module_rel: str
) -> list[str]:
    before = decision_sections_at(repo_root, before_ref, module_rel)
    after = decision_sections_at(repo_root, after_ref, module_rel)
    return sorted(
        decision_id
        for decision_id in set(before) | set(after)
        if before.get(decision_id) != after.get(decision_id)
    )


def _validate_receipts_for_ids(
    contract: dict[str, Any], decision_ids: list[str], *, checkpoint_commit: str | None
) -> dict[str, dict[str, Any]]:
    if any(item["status"] in {"pending", "answered"} for item in contract["items"]):
        raise DecisionGateError("仍有 PM 决策题未回答或未消费，不能提交或进入 ready_to_build。")
    owners: dict[str, dict[str, Any]] = {}
    for item in contract["items"]:
        if item["status"] != "consumed":
            continue
        bound = item.get("consumed_by")
        if checkpoint_commit is None and bound is not None:
            continue
        if checkpoint_commit is not None and (
            not isinstance(bound, dict) or bound.get("checkpoint_commit") != checkpoint_commit
        ):
            continue
        for decision_id in item["authorized_decision_ids"]:
            if decision_id in owners:
                raise DecisionGateError(f"决定 {decision_id} 被多个 PM 答复重复授权。")
            owners[decision_id] = item
    missing = sorted(set(decision_ids) - set(owners))
    extra = sorted(set(owners) - set(decision_ids))
    if missing:
        raise DecisionGateError(
            "产品模型决定缺少 PM 授权收据：" + "、".join(missing)
        )
    if extra:
        raise DecisionGateError(
            "PM 答复声明消费的决定没有进入本次授权变化：" + "、".join(extra)
        )
    return owners


def bind_ready_authorization(
    repo_root: Path,
    module_dir: Path,
    meta: dict[str, Any],
    *,
    checkpoint_commit: str,
) -> dict[str, Any]:
    module_rel = module_relative(repo_root, module_dir)
    raw_contract = meta.get("decision_gates")
    if raw_contract is None:
        checkpoint_sections = decision_sections_at(repo_root, checkpoint_commit, module_rel)
        if checkpoint_sections:
            raise DecisionGateError(
                "authorization_unverifiable：当前 ready 依据含产品决定，但没有 PM 授权收据；"
                "请退回 /pmai-design 重新确认。"
            )
        contract = new_contract(checkpoint_commit)
    else:
        contract = validate_contract(raw_contract, work_id=str(meta.get("id") or ""))
    baseline = contract["design_base_commit"]
    ancestry = _git(repo_root, "merge-base", "--is-ancestor", baseline, checkpoint_commit, check=False)
    if ancestry.returncode != 0:
        raise DecisionGateError("decision gate 的 design 基线不在当前 checkpoint 历史中。")
    changed = changed_decision_ids(
        repo_root, before_ref=baseline, after_ref=checkpoint_commit, module_rel=module_rel
    )
    owners = _validate_receipts_for_ids(contract, changed, checkpoint_commit=None)
    checkpoint_sections = decision_sections_at(repo_root, checkpoint_commit, module_rel)
    owner_hashes: dict[str, dict[str, str]] = {}
    owner_items: dict[str, dict[str, Any]] = {}
    for decision_id, item in owners.items():
        section = checkpoint_sections.get(decision_id)
        if section is None:
            raise DecisionGateError(f"checkpoint 中缺少已授权决定：{decision_id}")
        owner_items[item["gate_id"]] = item
        owner_hashes.setdefault(item["gate_id"], {})[decision_id] = sha256_text(section)
    for gate_id, item in owner_items.items():
        item["consumed_by"] = {
            "checkpoint_commit": checkpoint_commit,
            "decision_hashes": owner_hashes[gate_id],
            "bound_at": now_iso(),
        }
    contract["ready_authorization"] = {
        "status": "verified",
        "checkpoint_commit": checkpoint_commit,
        "decision_ids": changed,
        "verified_at": now_iso(),
    }
    normalized = validate_contract(contract, work_id=str(meta.get("id") or ""))
    meta["decision_gates"] = normalized
    return normalized["ready_authorization"]


def validate_ready_authorization(
    repo_root: Path, module_dir: Path, meta: dict[str, Any]
) -> dict[str, Any]:
    raw_contract = meta.get("decision_gates")
    if raw_contract is None:
        raise DecisionGateError(
            "authorization_unverifiable：ready_to_build 缺少 PM 授权收据；"
            "未开工工作必须退回 /pmai-design 重新确认。"
        )
    contract = validate_contract(raw_contract, work_id=str(meta.get("id") or ""))
    receipt = contract.get("ready_authorization")
    if not isinstance(receipt, dict) or receipt.get("status") != "verified":
        raise DecisionGateError("ready_to_build 缺少已验证的决定授权 checkpoint。")
    checkpoint = _require_string(meta.get("design_checkpoint_commit"), "design checkpoint")
    if receipt.get("checkpoint_commit") != checkpoint:
        raise DecisionGateError("决定授权收据与 design checkpoint 不一致。")
    module_rel = module_relative(repo_root, module_dir)
    changed = changed_decision_ids(
        repo_root,
        before_ref=contract["design_base_commit"],
        after_ref=checkpoint,
        module_rel=module_rel,
    )
    recorded = receipt.get("decision_ids")
    if not isinstance(recorded, list) or sorted(recorded) != changed:
        raise DecisionGateError("决定授权收据记录的决定集合与 checkpoint 实际变化不一致。")
    owners = _validate_receipts_for_ids(contract, changed, checkpoint_commit=checkpoint)
    sections = decision_sections_at(repo_root, checkpoint, module_rel)
    for decision_id, item in owners.items():
        bound = item["consumed_by"]
        if bound["decision_hashes"].get(decision_id) != sha256_text(sections[decision_id]):
            raise DecisionGateError(f"决定 {decision_id} 的授权内容 hash 已漂移。")
    return deepcopy(receipt)


def guard_authority_write(module_dir: Path) -> dict[str, Any]:
    meta = read_meta(module_dir)
    raw_contract = meta.get("decision_gates")
    if raw_contract is None:
        raise DecisionGateError("当前决定写入没有 decision gate 授权窗口。")
    contract = validate_contract(raw_contract, work_id=str(meta.get("id") or ""))
    pending = [item for item in contract["items"] if item["status"] == "pending"]
    if pending:
        raise DecisionGateError("当前 PM 决策题尚未回答，禁止写 decisions.md。")
    windows = [
        item
        for item in contract["items"]
        if item["status"] == "answered"
        or (item["status"] == "consumed" and item.get("consumed_by") is None)
    ]
    if len(windows) != 1:
        raise DecisionGateError("没有唯一、尚未 checkpoint 的 PM 授权答复，禁止写 decisions.md。")
    return {"status": "allowed", "gate_id": windows[0]["gate_id"]}


def guard_pending_write(module_dir: Path) -> dict[str, Any]:
    meta = read_meta(module_dir)
    raw_contract = meta.get("decision_gates")
    if raw_contract is None:
        return {"status": "allowed", "reason": "no_gate_contract"}
    contract = validate_contract(raw_contract, work_id=str(meta.get("id") or ""))
    pending = [item for item in contract["items"] if item["status"] == "pending"]
    if pending:
        raise DecisionGateError(
            "当前 PM 决策题尚未回答，禁止修改 discussion.md、spec.md 或项目建造定义。"
        )
    return {"status": "allowed"}


def _git_index_file(repo_root: Path, relative: str) -> str:
    result = _git(repo_root, "show", f":{relative}", check=False)
    if result.returncode == 0:
        return result.stdout
    return ""


def check_staged_authorization(repo_root: Path) -> dict[str, Any]:
    pending: list[str] = []
    for path in _active_meta_paths(repo_root):
        meta = read_meta(path.parent)
        raw = meta.get("decision_gates")
        if raw is None:
            continue
        contract = validate_contract(raw, work_id=str(meta.get("id") or ""))
        pending.extend(
            item["gate_id"]
            for item in contract["items"]
            if item["status"] in {"pending", "answered"}
        )
    if pending:
        raise DecisionGateError(
            "仍有 PM 决策题未回答或未消费，禁止提交：" + "、".join(pending)
        )

    staged = _git(
        repo_root, "diff", "--cached", "--name-only", "--diff-filter=ACMR"
    ).stdout.splitlines()
    checked: dict[str, list[str]] = {}
    for relative in staged:
        path = Path(relative)
        if len(path.parts) != 4 or path.parts[:2] != ("docs", "modules"):
            continue
        if path.name != "decisions.md":
            continue
        module_rel = Path(*path.parts[:-1]).as_posix()
        before = parse_decision_sections(_git_file(repo_root, "HEAD", relative))
        after = parse_decision_sections(_git_index_file(repo_root, relative))
        changed = sorted(
            decision_id
            for decision_id in set(before) | set(after)
            if before.get(decision_id) != after.get(decision_id)
        )
        if not changed:
            continue
        meta_rel = f"{module_rel}/.work-meta.json"
        staged_meta_text = _git_index_file(repo_root, meta_rel)
        if not staged_meta_text:
            raise DecisionGateError(
                f"{relative} 改变了产品决定，但同一提交未暂存 {meta_rel} 授权收据。"
            )
        try:
            staged_meta = json.loads(staged_meta_text)
        except json.JSONDecodeError as exc:
            raise DecisionGateError(f"暂存的 {meta_rel} 不是合法 JSON。") from exc
        contract = validate_contract(
            staged_meta.get("decision_gates"), work_id=str(staged_meta.get("id") or "")
        )
        _validate_receipts_for_ids(contract, changed, checkpoint_commit=None)
        checked[module_rel] = changed
    return {"status": "verified", "modules": checked}


def context_summary(meta: dict[str, Any]) -> dict[str, Any] | None:
    raw = meta.get("decision_gates")
    if raw is None:
        return None
    contract = validate_contract(raw, work_id=str(meta.get("id") or ""))
    return {
        "schema_version": contract["schema_version"],
        "design_base_commit": contract["design_base_commit"],
        "items": [
            {
                "gate_id": item["gate_id"],
                "question_id": item["question_id"],
                "kind": item["kind"],
                "status": item["status"],
                "question_summary": item["question"]["summary"],
                "displayed_message": item["question"]["displayed_message"],
                "answer_candidates": deepcopy(item["answer_candidates"]),
                "answer": deepcopy(item["answer"]),
                "authorized_decision_ids": list(item["authorized_decision_ids"]),
                "consumed_by": deepcopy(item["consumed_by"]),
            }
            for item in contract["items"]
        ],
        "ready_authorization": deepcopy(contract["ready_authorization"]),
    }
