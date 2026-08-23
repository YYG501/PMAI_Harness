"""Machine-verifiable PM answer binding for product and module decisions.

Module gates live inside the active module's ``.work-meta.json``.  Product and
stage-routing gates use the ignored project runtime ledger under
``.pm-workflow/context/``.  Both stores use the same question/event contract:
the receipt proves which displayed question and user message authorized an
action, while product documents remain the only business truth.
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
VALID_GATE_KINDS = {
    "product-model",
    "project-definition",
    "one-way-door",
    "shared-understanding",
}
VALID_GATE_MODES = {"sequential", "frontier"}
DECISION_ID_RE = re.compile(r"^D[0-9]+$", re.IGNORECASE)
DECISION_HEADING_RE = re.compile(r"^#{2,6}\s+(D[0-9]+)\b.*$", re.IGNORECASE)
SHORT_ANSWER_LIMIT = 2048
PROJECT_GATE_RELATIVE = Path(".pm-workflow/context/decision-gates.json")
PROJECT_GATE_WORK_ID = "project"
PROJECT_PROPOSAL_PATHS = {
    ".pm-workflow/proposal.json",
    "PRODUCT.md",
    "docs/proposals/INDEX.md",
}
PROJECT_PROPOSAL_BODY_RE = re.compile(r"^docs/proposals/[^/]+\.md$")


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


def project_gate_path(repo_root: Path) -> Path:
    root = repo_root.expanduser().resolve()
    try:
        root.relative_to(root)
    except ValueError as exc:  # pragma: no cover - defensive path guard
        raise DecisionGateError(f"项目根目录无效：{repo_root}") from exc
    return root / PROJECT_GATE_RELATIVE


def read_project_contract(repo_root: Path, *, create: bool = False) -> dict[str, Any]:
    path = project_gate_path(repo_root)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        if not create:
            try:
                baseline = git_head(repo_root)
            except DecisionGateError:
                # Fresh init runs the pre-commit checks before the first HEAD
                # exists. No project gate can be open in that state.
                baseline = "unborn"
            return new_contract(baseline)
        value = new_contract(git_head(repo_root))
    except json.JSONDecodeError as exc:
        raise DecisionGateError(f"项目级 decision gate 不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise DecisionGateError("项目级 decision gate 顶层必须是对象。")
    return validate_contract(value, work_id=PROJECT_GATE_WORK_ID)


def write_project_contract(repo_root: Path, contract: dict[str, Any]) -> None:
    path = project_gate_path(repo_root)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(contract, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
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
    answer_event_owners: dict[str, tuple[str, str, str]] = {}
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
        mode = str(raw.get("mode") or "sequential").strip()
        if mode not in VALID_GATE_MODES:
            raise DecisionGateError(f"{label}.mode 不受支持：{mode}")
        round_id = str(raw.get("round_id") or "").strip()
        if mode == "frontier" and not round_id:
            raise DecisionGateError(f"{label}.frontier gate 必须有 round_id。")
        if mode == "sequential" and not round_id:
            round_id = gate_id

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
            "round_position": question.get("round_position"),
            "round_summary": str(question.get("round_summary") or "").strip() or None,
        }
        if (
            sha256_text(normalized_question["displayed_message"])
            != normalized_question["displayed_message_sha256"]
        ):
            raise DecisionGateError(f"{label} 的展示消息 hash 不匹配。")
        if kind == "shared-understanding":
            if mode != "sequential":
                raise DecisionGateError(f"{label} shared-understanding 必须使用 sequential mode。")
            if (
                len(normalized_question["options"]) != 1
                or normalized_question["options"][0]["id"] != "confirm"
            ):
                raise DecisionGateError(
                    f"{label} shared-understanding 只能有一个 confirm 选项。"
                )

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
            owner = answer_event_owners.setdefault(event_id, (item_work_id, mode, round_id))
            if owner != (item_work_id, mode, round_id):
                raise DecisionGateError("同一用户答复事件不能跨工作、跨轮次绑定。")

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
                "free_text": str(answer.get("free_text") or "").strip() or None,
                "answered_at": _require_string(
                    answer.get("answered_at"), f"{label}.answer.answered_at"
                ),
            }
            option_ids = {option["id"] for option in normalized_question["options"]}
            selected_option_id = normalized_answer["selected_option_id"]
            free_text = normalized_answer["free_text"]
            if selected_option_id is not None and selected_option_id not in option_ids:
                raise DecisionGateError(f"{label}.answer 选择了本题不存在的选项。")
            if selected_option_id is not None and free_text is not None:
                raise DecisionGateError(f"{label}.answer 不能同时选择选项和自由回答。")
            if free_text is not None and not normalized_question["allow_free_text"]:
                raise DecisionGateError(f"{label}.answer 不允许自由回答。")
            if mode == "frontier" and selected_option_id is None and free_text is None:
                raise DecisionGateError(f"{label}.frontier answer 必须明确选择选项或自由回答。")

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

        artifacts = raw.get("authorized_artifacts", [])
        if not isinstance(artifacts, list):
            raise DecisionGateError(f"{label}.authorized_artifacts 必须是数组。")
        normalized_artifacts: list[str] = []
        for raw_artifact in artifacts:
            artifact = _require_string(raw_artifact, f"{label}.authorized_artifacts")
            if artifact not in normalized_artifacts:
                normalized_artifacts.append(artifact)

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
        if status == "consumed" and not normalized_ids and not normalized_artifacts:
            raise DecisionGateError(f"{label} consumed 时必须绑定决定 ID 或项目动作。")
        if kind == "shared-understanding":
            if normalized_ids:
                raise DecisionGateError(
                    f"{label} shared-understanding 不能绑定产品决定 ID。"
                )
            if status == "consumed" and normalized_artifacts != ["shared-understanding"]:
                raise DecisionGateError(
                    f"{label} shared-understanding 必须绑定 shared-understanding 收据。"
                )
        elif normalized_artifacts and item_work_id != PROJECT_GATE_WORK_ID:
            raise DecisionGateError(f"{label} 普通 decision gate 不能绑定项目动作。")
        if status == "consumed" and not str(raw.get("consumed_at") or "").strip():
            raise DecisionGateError(f"{label} consumed 时必须记录 consumed_at。")
        if status != "consumed" and (
            normalized_ids or normalized_artifacts or consumed_by is not None
        ):
            raise DecisionGateError(f"{label} 未 consumed 时不能绑定决定或 checkpoint。")

        normalized_items.append(
            {
                "gate_id": gate_id,
                "question_id": question_id,
                "work_id": item_work_id,
                "kind": kind,
                "mode": mode,
                "round_id": round_id,
                "status": status,
                "question": normalized_question,
                "answer_candidates": candidates,
                "answer": normalized_answer,
                "authorized_decision_ids": normalized_ids,
                "authorized_artifacts": normalized_artifacts,
                "consumed_at": str(raw.get("consumed_at") or "").strip() or None,
                "consumed_by": consumed_by,
                "cancelled_at": str(raw.get("cancelled_at") or "").strip() or None,
                "cancel_reason": str(raw.get("cancel_reason") or "").strip() or None,
            }
        )

    unresolved_items = [
        item for item in normalized_items if item["status"] in {"pending", "answered"}
    ]
    if unresolved_items:
        groups = {
            (item["work_id"], item["mode"], item["round_id"])
            for item in unresolved_items
        }
        if len(unresolved_items) > 1 and (
            any(item["mode"] != "frontier" for item in unresolved_items) or len(groups) != 1
        ):
            raise DecisionGateError("同一工作只能有一个 sequential gate，或同一 frontier round 的多个问题。")
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


def _new_gate_item(
    *,
    work_id: str,
    kind: str,
    summary: str,
    displayed_message: str,
    options: list[dict[str, str]],
    allow_free_text: bool,
    session_id: str | None,
    display_message_id: str | None,
    mode: str = "sequential",
    round_id: str | None = None,
) -> dict[str, Any]:
    if kind not in VALID_GATE_KINDS:
        raise DecisionGateError(f"不支持的 decision gate kind：{kind}")
    stamp = now_iso()
    entropy = sha256_text("\n".join([work_id, summary, displayed_message, stamp]))[:12]
    normalized_mode = _require_string(mode, "gate mode")
    if normalized_mode not in VALID_GATE_MODES:
        raise DecisionGateError(f"不支持的 gate mode：{normalized_mode}")
    normalized_round = (round_id or "").strip() or f"round-{entropy}"
    return {
        "gate_id": f"gate-{entropy}",
        "question_id": f"question-{entropy}",
        "work_id": _require_string(work_id, "work id"),
        "kind": kind,
        "mode": normalized_mode,
        "round_id": normalized_round,
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
        "authorized_artifacts": [],
        "consumed_at": None,
        "consumed_by": None,
        "cancelled_at": None,
        "cancel_reason": None,
    }


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
    item = _new_gate_item(
        work_id=_require_string(meta.get("id"), "work id"),
        kind=kind,
        summary=summary,
        displayed_message=displayed_message,
        options=options,
        allow_free_text=allow_free_text,
        session_id=session_id,
        display_message_id=display_message_id,
    )
    contract["items"].append(item)
    contract["ready_authorization"] = None
    meta["decision_gates"] = validate_contract(contract, work_id=item["work_id"])
    write_meta(module_dir, meta)
    return item


def open_round(
    module_dir: Path,
    *,
    kind: str,
    round_summary: str,
    questions: list[dict[str, Any]],
    session_id: str | None,
    display_message_id: str | None,
) -> list[dict[str, Any]]:
    """Open one Design frontier round containing independent questions."""
    if not questions:
        raise DecisionGateError("frontier round 至少需要一个问题。")
    meta = read_meta(module_dir)
    if str(meta.get("lifecycle_state") or "") != "designing":
        raise DecisionGateError("只有 designing 工作可以打开 frontier round。")
    repo_root = repo_root_for(module_dir)
    contract = ensure_contract(meta, baseline_commit=git_head(repo_root))
    if any(item["status"] in {"pending", "answered"} for item in contract["items"]):
        raise DecisionGateError("当前工作已有未完成问题，不能同时打开下一轮。")
    round_id = f"round-{secrets.token_hex(8)}"
    created: list[dict[str, Any]] = []
    for index, question in enumerate(questions, start=1):
        if not isinstance(question, dict):
            raise DecisionGateError(f"frontier question[{index}] 必须是对象。")
        try:
            summary = _require_string(question.get("summary"), f"question[{index}].summary")
            message = _require_string(question.get("message"), f"question[{index}].message")
            options = _validate_options(question.get("options"), f"question[{index}].options")
        except KeyError as exc:  # pragma: no cover - defensive
            raise DecisionGateError(f"question[{index}] 缺少字段：{exc}") from exc
        item = _new_gate_item(
            work_id=_require_string(meta.get("id"), "work id"),
            kind=kind,
            summary=summary,
            displayed_message=message,
            options=options,
            allow_free_text=question.get("allow_free_text") is True,
            session_id=session_id,
            display_message_id=display_message_id,
            mode="frontier",
            round_id=round_id,
        )
        item["question"]["round_position"] = index
        item["question"]["round_summary"] = _require_string(round_summary, "round summary")
        created.append(item)
    contract["items"].extend(created)
    contract["ready_authorization"] = None
    meta["decision_gates"] = validate_contract(contract, work_id=created[0]["work_id"])
    write_meta(module_dir, meta)
    return created


def open_shared_understanding(
    module_dir: Path,
    *,
    summary: str,
    displayed_message: str,
    session_id: str | None,
    display_message_id: str | None,
) -> dict[str, Any]:
    """Record Grill's final shared-understanding confirmation question."""
    meta = read_meta(module_dir)
    if str(meta.get("lifecycle_state") or "") != "designing":
        raise DecisionGateError("只有 designing 工作可以请求 shared-understanding 确认。")
    repo_root = repo_root_for(module_dir)
    contract = ensure_contract(meta, baseline_commit=git_head(repo_root))
    frontier = [
        item
        for item in contract["items"]
        if item["mode"] == "frontier" and item["kind"] != "shared-understanding"
    ]
    if not frontier:
        raise DecisionGateError("当前工作没有 frontier round，不能请求 shared-understanding 确认。")
    if any(item["status"] in {"pending", "answered"} for item in frontier):
        raise DecisionGateError("frontier 仍有未闭合问题，不能请求 shared-understanding 确认。")
    if any(
        item["kind"] == "shared-understanding" and item["status"] in {"pending", "answered"}
        for item in contract["items"]
    ):
        raise DecisionGateError("当前已有 shared-understanding 确认等待处理。")
    item = _new_gate_item(
        work_id=_require_string(meta.get("id"), "work id"),
        kind="shared-understanding",
        summary=summary,
        displayed_message=displayed_message,
        options=[{"id": "confirm", "label": "确认我们理解一致"}],
        allow_free_text=False,
        session_id=session_id,
        display_message_id=display_message_id,
        mode="sequential",
        round_id=f"shared-{secrets.token_hex(8)}",
    )
    item["question"]["round_summary"] = _require_string(summary, "shared-understanding summary")
    contract["items"].append(item)
    contract["ready_authorization"] = None
    meta["decision_gates"] = validate_contract(contract, work_id=item["work_id"])
    write_meta(module_dir, meta)
    return item


def open_project_gate(
    repo_root: Path,
    *,
    kind: str,
    summary: str,
    displayed_message: str,
    options: list[dict[str, str]],
    allow_free_text: bool,
    session_id: str | None,
    display_message_id: str | None,
) -> dict[str, Any]:
    root = repo_root.expanduser().resolve()
    contract = read_project_contract(root, create=True)
    if any(item["status"] in {"pending", "answered"} for item in contract["items"]):
        raise DecisionGateError("当前项目已有一题等待答复或消费，不能同时打开下一题。")
    item = _new_gate_item(
        work_id=PROJECT_GATE_WORK_ID,
        kind=kind,
        summary=summary,
        displayed_message=displayed_message,
        options=options,
        allow_free_text=allow_free_text,
        session_id=session_id,
        display_message_id=display_message_id,
    )
    contract["items"].append(item)
    contract["ready_authorization"] = None
    normalized = validate_contract(contract, work_id=PROJECT_GATE_WORK_ID)
    write_project_contract(root, normalized)
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

    candidates: list[tuple[str, Path, dict[str, Any] | None, dict[str, Any], dict[str, Any]]] = []
    all_events: dict[str, tuple[str, str, str, str]] = {}
    project_contract = read_project_contract(repo_root)
    for item in project_contract["items"]:
        for event in item["answer_candidates"]:
            all_events[event["event_id"]] = (
                "project",
                PROJECT_GATE_WORK_ID,
                item["mode"],
                item["round_id"],
            )
        if item["status"] != "pending":
            continue
        display_session = item["question"].get("display_session_id")
        if display_session and display_session != session_id:
            continue
        candidates.append(("project", repo_root, None, project_contract, item))
    for path in _active_meta_paths(repo_root):
        module_dir = path.parent
        meta = read_meta(module_dir)
        raw_contract = meta.get("decision_gates")
        if raw_contract is None:
            continue
        contract = validate_contract(raw_contract, work_id=str(meta.get("id") or ""))
        for item in contract["items"]:
            for event in item["answer_candidates"]:
                all_events[event["event_id"]] = (
                    "module",
                    str(meta.get("id") or ""),
                    item["mode"],
                    item["round_id"],
                )
            if item["status"] != "pending":
                continue
            display_session = item["question"].get("display_session_id")
            if display_session and display_session != session_id:
                continue
            candidates.append(("module", module_dir, meta, contract, item))

    if not candidates:
        return {"status": "none", "reason": "当前没有已展示且 pending 的 decision gate。"}
    groups = {
        (
            scope,
            str((meta or {}).get("id") if meta is not None else PROJECT_GATE_WORK_ID),
            item["mode"],
            item["round_id"],
        )
        for scope, _target, meta, _contract, item in candidates
    }
    if len(groups) != 1:
        return {
            "status": "ambiguous",
            "reason": "当前消息可能对应多个 pending decision gate，未绑定任何问题。",
            "gate_ids": [item[4]["gate_id"] for item in candidates],
        }
    scope, target, meta, contract, item = candidates[0]
    event_id = _event_id(
        session_id=session_id,
        message_id=message_id,
        transcript_path=transcript_path,
        message=answer_text,
    )
    owner = all_events.get(event_id)
    group_key = (
        scope,
        str(meta.get("id") or "") if meta is not None else PROJECT_GATE_WORK_ID,
        item["mode"],
        item["round_id"],
    )
    if owner and owner != group_key:
        raise DecisionGateError("同一用户答复事件已经属于另一个 decision gate。")
    event = {
            "event_id": event_id,
            "session_id": (session_id or "").strip() or None,
            "message_id": (message_id or "").strip() or None,
            "message": answer_text,
            "message_sha256": sha256_text(answer_text),
            "observed_at": now_iso(),
            "source": "user_prompt_submit",
        }
    group_items = [candidate[4] for candidate in candidates]
    for candidate_item in group_items:
        if not any(event_id == existing["event_id"] for existing in candidate_item["answer_candidates"]):
            candidate_item["answer_candidates"].append(event)
    normalized = validate_contract(
        contract,
        work_id=(str(meta.get("id") or "") if meta is not None else PROJECT_GATE_WORK_ID),
    )
    if scope == "project":
        write_project_contract(repo_root, normalized)
    else:
        assert meta is not None
        meta["decision_gates"] = normalized
        write_meta(target, meta)
    is_frontier = item["mode"] == "frontier"
    payload = {
        "status": "observed_round" if is_frontier else "observed",
        "scope": scope,
        "module": module_relative(repo_root, target) if scope == "module" else None,
        "event_id": event_id,
        "gate_id": item["gate_id"],
        "question_id": item["question_id"],
        "kind": item["kind"],
        "question_summary": item["question"]["summary"],
    }
    if is_frontier:
        payload["gate_ids"] = [candidate["gate_id"] for candidate in group_items]
        payload["question_ids"] = [candidate["question_id"] for candidate in group_items]
        payload["question_summaries"] = [candidate["question"]["summary"] for candidate in group_items]
    return payload


def _find_gate(contract: dict[str, Any], gate_id: str) -> dict[str, Any]:
    for item in contract["items"]:
        if item["gate_id"] == gate_id:
            return item
    raise DecisionGateError(f"找不到 decision gate：{gate_id}")


def _answer_item(
    contract: dict[str, Any],
    item: dict[str, Any],
    *,
    event_id: str,
    selected_option_id: str | None = None,
    explicit_free_text: str | None = None,
) -> dict[str, Any]:
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
    if selected_option_id and explicit_free_text is not None:
        raise DecisionGateError("同一题不能同时选择选项和提交自由回答。")
    selected = option_by_id.get(selected_option_id) if selected_option_id else None
    if selected_option_id and selected is None:
        raise DecisionGateError("frontier round 指定了本题不存在的选项。")
    free_text = None
    if explicit_free_text is not None:
        free_text = _require_string(explicit_free_text, "frontier free-text answer")
        if not item["question"]["allow_free_text"]:
            raise DecisionGateError("本题不允许自由回答。")
    else:
        selected = selected or option_by_id.get(answer_text) or option_by_label.get(answer_text)
    if selected is None and free_text is None and re.fullmatch(r"[0-9]+", answer_text):
        raise DecisionGateError("数字答复不属于本题展示的任何选项。")
    if selected is None and free_text is None and not item["question"]["allow_free_text"]:
        raise DecisionGateError("答复没有匹配本题选项；请让 PM 重新回答当前问题。")
    if selected is None and free_text is None:
        free_text = answer_text
    item["status"] = "answered"
    item["answer"] = {
        "event": event,
        "selected_option_id": selected["id"] if selected else None,
        "free_text": free_text,
        "answered_at": now_iso(),
    }
    return item


def answer_gate(module_dir: Path, *, gate_id: str, event_id: str) -> dict[str, Any]:
    meta = read_meta(module_dir)
    contract = validate_contract(meta.get("decision_gates"), work_id=str(meta.get("id") or ""))
    item = _find_gate(contract, gate_id)
    if item["mode"] == "frontier":
        raise DecisionGateError("frontier 问题必须使用 answer-round 显式绑定回答范围。")
    item = _answer_item(contract, item, event_id=event_id)
    meta["decision_gates"] = validate_contract(contract, work_id=str(meta.get("id") or ""))
    write_meta(module_dir, meta)
    return item


def answer_round(
    module_dir: Path,
    *,
    event_id: str,
    selections: dict[str, str],
    free_texts: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """Answer an explicit subset of questions in one frontier round."""
    normalized_free_texts = free_texts or {}
    if not selections and not normalized_free_texts:
        raise DecisionGateError("answer-round 至少需要一个 selection 或 free-text 回答。")
    overlap = sorted(set(selections) & set(normalized_free_texts))
    if overlap:
        raise DecisionGateError("同一题不能同时 selection 和 free-text：" + "、".join(overlap))
    meta = read_meta(module_dir)
    contract = validate_contract(meta.get("decision_gates"), work_id=str(meta.get("id") or ""))
    answer_ids = list(selections) + list(normalized_free_texts)
    selected_items = [_find_gate(contract, gate_id) for gate_id in answer_ids]
    groups = {(item["work_id"], item["mode"], item["round_id"]) for item in selected_items}
    if len(groups) != 1 or next(iter(groups))[1] != "frontier":
        raise DecisionGateError("answer-round 只能回答同一 frontier round 的问题。")
    answered: list[dict[str, Any]] = []
    for item in selected_items:
        answered.append(
            _answer_item(
                contract,
                item,
                event_id=event_id,
                selected_option_id=selections.get(item["gate_id"]),
                explicit_free_text=normalized_free_texts.get(item["gate_id"]),
            )
        )
    meta["decision_gates"] = validate_contract(contract, work_id=str(meta.get("id") or ""))
    write_meta(module_dir, meta)
    return answered


def confirm_shared_understanding(
    module_dir: Path, *, gate_id: str, event_id: str
) -> dict[str, Any]:
    """Confirm the displayed shared-understanding summary without creating a D."""
    meta = read_meta(module_dir)
    contract = validate_contract(meta.get("decision_gates"), work_id=str(meta.get("id") or ""))
    item = _find_gate(contract, gate_id)
    if item["kind"] != "shared-understanding":
        raise DecisionGateError("confirm-shared 只能确认 shared-understanding 收据。")
    _answer_item(contract, item, event_id=event_id, selected_option_id="confirm")
    meta["decision_gates"] = validate_contract(contract, work_id=str(meta.get("id") or ""))
    write_meta(module_dir, meta)
    return item


def answer_project_gate(repo_root: Path, *, gate_id: str, event_id: str) -> dict[str, Any]:
    root = repo_root.expanduser().resolve()
    contract = read_project_contract(root)
    item = _answer_item(contract, _find_gate(contract, gate_id), event_id=event_id)
    write_project_contract(root, validate_contract(contract, work_id=PROJECT_GATE_WORK_ID))
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


def consume_shared_understanding(module_dir: Path, *, gate_id: str) -> dict[str, Any]:
    """Consume the shared-understanding receipt as a non-product artifact."""
    meta = read_meta(module_dir)
    contract = validate_contract(meta.get("decision_gates"), work_id=str(meta.get("id") or ""))
    item = _find_gate(contract, gate_id)
    if item["kind"] != "shared-understanding":
        raise DecisionGateError("consume-shared 只能消费 shared-understanding 收据。")
    if item["status"] != "answered":
        raise DecisionGateError(f"shared-understanding 当前为 {item['status']}，不能消费。")
    item["status"] = "consumed"
    item["authorized_decision_ids"] = []
    item["authorized_artifacts"] = ["shared-understanding"]
    item["consumed_at"] = now_iso()
    item["consumed_by"] = None
    contract["ready_authorization"] = None
    meta["decision_gates"] = validate_contract(contract, work_id=str(meta.get("id") or ""))
    write_meta(module_dir, meta)
    return item


def consume_project_gate(
    repo_root: Path, *, gate_id: str, artifact: str
) -> dict[str, Any]:
    root = repo_root.expanduser().resolve()
    contract = read_project_contract(root)
    item = _find_gate(contract, gate_id)
    if item["status"] != "answered":
        raise DecisionGateError(f"decision gate 当前为 {item['status']}，不能消费。")
    artifact_value = _require_string(artifact, "项目动作")
    if artifact_value not in {"proposal:draft", "proposal:accept"} and not artifact_value.startswith("route:"):
        raise DecisionGateError(
            "项目动作必须是 proposal:draft、proposal:accept 或 route:<动作>。"
        )
    if artifact_value in {
        existing
        for other in contract["items"]
        if other["status"] == "consumed"
        for existing in other.get("authorized_artifacts", [])
    }:
        raise DecisionGateError(f"项目动作已经由其它答复消费：{artifact_value}")
    item["status"] = "consumed"
    item["authorized_decision_ids"] = []
    item["authorized_artifacts"] = [artifact_value]
    item["consumed_at"] = now_iso()
    item["consumed_by"] = None
    write_project_contract(root, validate_contract(contract, work_id=PROJECT_GATE_WORK_ID))
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


def cancel_project_gate(repo_root: Path, *, gate_id: str, reason: str) -> dict[str, Any]:
    root = repo_root.expanduser().resolve()
    contract = read_project_contract(root)
    item = _find_gate(contract, gate_id)
    if item["status"] not in {"pending", "answered"}:
        raise DecisionGateError(f"decision gate 当前为 {item['status']}，不能取消。")
    item["status"] = "cancelled"
    item["cancelled_at"] = now_iso()
    item["cancel_reason"] = _require_string(reason, "cancel reason")
    item["answer"] = None
    write_project_contract(root, validate_contract(contract, work_id=PROJECT_GATE_WORK_ID))
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
    frontier_items = [
        item
        for item in contract["items"]
        if item["mode"] == "frontier" and item["kind"] != "shared-understanding"
    ]
    shared_item = _frontier_shared_item(contract)
    if frontier_items:
        if shared_item is None or shared_item["status"] != "consumed":
            raise DecisionGateError(
                "frontier 已清空但缺少已消费的 shared-understanding 确认，不能进入 ready_to_build。"
            )
        if shared_item.get("consumed_by") is not None and shared_item["consumed_by"].get(
            "checkpoint_commit"
        ) != checkpoint_commit:
            raise DecisionGateError("shared-understanding 确认不属于当前 design checkpoint。")
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
    if shared_item is not None and shared_item["status"] == "consumed":
        if shared_item.get("consumed_by") is None:
            shared_item["consumed_by"] = {
                "checkpoint_commit": checkpoint_commit,
                "decision_hashes": {},
                "bound_at": now_iso(),
            }
    contract["ready_authorization"] = {
        "status": "verified",
        "checkpoint_commit": checkpoint_commit,
        "decision_ids": changed,
        "shared_understanding_gate_id": shared_item["gate_id"] if shared_item else None,
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
    frontier_items = [
        item
        for item in contract["items"]
        if item["mode"] == "frontier" and item["kind"] != "shared-understanding"
    ]
    if frontier_items:
        shared_item = _frontier_shared_item(contract)
        expected_shared_id = receipt.get("shared_understanding_gate_id")
        if (
            shared_item is None
            or shared_item["gate_id"] != expected_shared_id
            or shared_item["status"] != "consumed"
        ):
            raise DecisionGateError(
                "ready 授权缺少当前 frontier 的 shared-understanding 确认。"
            )
        bound = shared_item.get("consumed_by")
        if not isinstance(bound, dict) or bound.get("checkpoint_commit") != checkpoint:
            raise DecisionGateError("shared-understanding 确认与 design checkpoint 不一致。")
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
        if item["kind"] != "shared-understanding"
        if item["status"] == "answered"
        or (item["status"] == "consumed" and item.get("consumed_by") is None)
    ]
    if not windows:
        raise DecisionGateError("没有唯一、尚未 checkpoint 的 PM 授权答复，禁止写 decisions.md。")
    return {
        "status": "allowed",
        "gate_id": windows[0]["gate_id"] if len(windows) == 1 else None,
        "gate_ids": [item["gate_id"] for item in windows],
        "round_ids": sorted({item["round_id"] for item in windows}),
    }


def guard_pending_write(module_dir: Path, *, artifact: str | None = None) -> dict[str, Any]:
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
    shared_waiting = [
        item
        for item in contract["items"]
        if item["kind"] == "shared-understanding"
        and item["status"] in {"pending", "answered"}
    ]
    if shared_waiting:
        raise DecisionGateError(
            "frontier 已清空但 shared-understanding 尚未确认并消费，禁止继续写入最终设计。"
        )
    if artifact == "spec":
        frontier = [
            item
            for item in contract["items"]
            if item["mode"] == "frontier" and item["kind"] != "shared-understanding"
        ]
        shared_item = _frontier_shared_item(contract)
        if frontier and (shared_item is None or shared_item["status"] != "consumed"):
            raise DecisionGateError(
                "frontier 已清空但还没有 shared-understanding 确认，禁止写入 spec.md。"
            )
    return {"status": "allowed"}


def guard_project_write(repo_root: Path) -> dict[str, Any]:
    contract = read_project_contract(repo_root)
    pending = [item for item in contract["items"] if item["status"] == "pending"]
    if pending:
        raise DecisionGateError(
            "当前项目级决策题尚未回答，禁止修改 Proposal 或产品基线。"
        )
    windows = [item for item in contract["items"] if item["status"] == "answered"]
    if len(windows) != 1:
        raise DecisionGateError(
            "没有唯一、尚未消费的项目级 PM 授权答复，禁止修改 Proposal 或产品基线。"
        )
    return {"status": "allowed", "gate_id": windows[0]["gate_id"]}


def _git_index_file(repo_root: Path, relative: str) -> str:
    result = _git(repo_root, "show", f":{relative}", check=False)
    if result.returncode == 0:
        return result.stdout
    return ""


def _has_git_head(repo_root: Path) -> bool:
    return _git(repo_root, "rev-parse", "--verify", "HEAD", check=False).returncode == 0


def _project_artifact_owners(contract: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    owners: dict[str, list[dict[str, Any]]] = {}
    for item in contract["items"]:
        if item["status"] != "consumed":
            continue
        for artifact in item.get("authorized_artifacts", []):
            owners.setdefault(artifact, []).append(item)
    return owners


def _project_proposal_paths(staged: list[str]) -> list[str]:
    return [
        relative
        for relative in staged
        if relative in PROJECT_PROPOSAL_PATHS or PROJECT_PROPOSAL_BODY_RE.fullmatch(relative)
    ]


def _frontier_shared_item(contract: dict[str, Any]) -> dict[str, Any] | None:
    frontier_indexes = [
        index
        for index, item in enumerate(contract["items"])
        if item["mode"] == "frontier" and item["kind"] != "shared-understanding"
    ]
    if not frontier_indexes:
        return None
    shared_items = [
        (index, item)
        for index, item in enumerate(contract["items"])
        if item["kind"] == "shared-understanding"
    ]
    if not shared_items or shared_items[-1][0] < frontier_indexes[-1]:
        return None
    return shared_items[-1][1]


def check_staged_authorization(repo_root: Path) -> dict[str, Any]:
    pending: list[str] = []
    project_contract = read_project_contract(repo_root)
    pending.extend(
        f"project:{item['gate_id']}"
        for item in project_contract["items"]
        if item["status"] in {"pending", "answered"}
    )
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
    for relative in staged:
        match = re.fullmatch(r"docs/modules/([^/]+)/spec\.md", relative)
        if not match:
            continue
        module_rel = f"docs/modules/{match.group(1)}"
        staged_meta_text = _git_index_file(repo_root, f"{module_rel}/.work-meta.json")
        if not staged_meta_text:
            continue
        try:
            staged_meta = json.loads(staged_meta_text)
        except json.JSONDecodeError as exc:
            raise DecisionGateError(f"暂存的 {module_rel}/.work-meta.json 不是合法 JSON。") from exc
        contract = validate_contract(
            staged_meta.get("decision_gates"), work_id=str(staged_meta.get("id") or "")
        )
        frontier = [
            item
            for item in contract["items"]
            if item["mode"] == "frontier" and item["kind"] != "shared-understanding"
        ]
        shared_item = _frontier_shared_item(contract)
        if frontier and (shared_item is None or shared_item["status"] != "consumed"):
            raise DecisionGateError(
                f"{relative} 写入前必须完成 frontier 的 shared-understanding 确认。"
            )
    project_paths = _project_proposal_paths(staged)
    # The initializer's first commit contains the required PRODUCT.md marker
    # before any project question exists. Once HEAD exists, the same paths
    # require a fresh project receipt.
    if project_paths and not project_gate_path(repo_root).exists() and not _has_git_head(repo_root):
        project_paths = []
    if project_paths:
        owners = _project_artifact_owners(project_contract)
        accept = owners.get("proposal:accept", [])
        draft = owners.get("proposal:draft", [])
        if ".pm-workflow/proposal.json" in project_paths or "PRODUCT.md" in project_paths:
            if not accept:
                raise DecisionGateError(
                    "Proposal 原子提交修改了 proposal.json 或 PRODUCT.md，但没有本轮已消费的 proposal:accept 收据。"
                )
        elif not (accept or draft):
            raise DecisionGateError(
                "Proposal 文件提交缺少本轮已消费的 proposal:draft 或 proposal:accept 收据。"
            )
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
                "mode": item["mode"],
                "round_id": item["round_id"],
                "status": item["status"],
                "question_summary": item["question"]["summary"],
                "displayed_message": item["question"]["displayed_message"],
                "answer_candidates": deepcopy(item["answer_candidates"]),
                "answer": deepcopy(item["answer"]),
                "authorized_decision_ids": list(item["authorized_decision_ids"]),
                "authorized_artifacts": list(item.get("authorized_artifacts", [])),
                "consumed_by": deepcopy(item["consumed_by"]),
            }
            for item in contract["items"]
        ],
        "ready_authorization": deepcopy(contract["ready_authorization"]),
    }


def project_context_summary(repo_root: Path) -> dict[str, Any]:
    contract = read_project_contract(repo_root)
    return {
        "schema_version": contract["schema_version"],
        "design_base_commit": contract["design_base_commit"],
        "items": [
            {
                "gate_id": item["gate_id"],
                "question_id": item["question_id"],
                "kind": item["kind"],
                "mode": item["mode"],
                "round_id": item["round_id"],
                "status": item["status"],
                "question_summary": item["question"]["summary"],
                "displayed_message": item["question"]["displayed_message"],
                "answer_candidates": deepcopy(item["answer_candidates"]),
                "answer": deepcopy(item["answer"]),
                "authorized_artifacts": list(item.get("authorized_artifacts", [])),
            }
            for item in contract["items"]
        ],
    }
