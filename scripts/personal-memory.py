#!/usr/bin/env python3
"""Store and recall PMAI personal experience without changing project truth.

Personal memory is user-level, advisory state. Project facts and decisions stay
in the consumer repository and continue to be compiled by context-pack.py.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
DEFAULT_CONTEXT_BUDGET = 8000
SAFETY_MAX_CANDIDATES = 512
RECALL_DUPLICATE_THRESHOLD = 0.86
ACTIVE = "active"
SUPERSEDED = "superseded"
FORGOTTEN = "forgotten"

SIGNAL_CONFIDENCE = {
    "explicit_correction": 0.55,
    "accepted_recovery": 0.60,
    "audit_finding": 0.65,
    "explicit_generalization": 0.90,
}


class MemoryError(RuntimeError):
    """User-facing personal-memory failure."""


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def new_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:12]}"


def state_home(value: str | None) -> Path:
    raw = value or os.environ.get("PMAI_STATE_HOME") or "~/.pmai-state"
    return Path(raw).expanduser().resolve()


def db_path(args: argparse.Namespace) -> Path:
    return state_home(args.state_home) / "personal-memory.sqlite3"


def ensure_private_path(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        path.parent.chmod(0o700)
    except OSError:
        pass


def connect(path: Path, *, create: bool) -> sqlite3.Connection | None:
    if not create and not path.exists():
        return None
    ensure_private_path(path)
    try:
        conn = sqlite3.connect(path)
    except sqlite3.Error as exc:
        raise MemoryError(f"无法打开个人经验库: {exc}") from exc
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA busy_timeout = 3000")
    initialize_schema(conn)
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return conn


def initialize_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS episodes (
            id TEXT PRIMARY KEY,
            created_at TEXT NOT NULL,
            skill TEXT NOT NULL,
            signal TEXT NOT NULL,
            disposition TEXT NOT NULL,
            context_summary TEXT NOT NULL DEFAULT '',
            failed_behavior TEXT NOT NULL DEFAULT '',
            user_feedback TEXT NOT NULL DEFAULT '',
            corrected_behavior TEXT NOT NULL DEFAULT '',
            outcome TEXT NOT NULL DEFAULT '',
            evidence_ref TEXT NOT NULL DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            applies_when TEXT NOT NULL,
            lesson TEXT NOT NULL,
            reason TEXT NOT NULL DEFAULT '',
            boundaries TEXT NOT NULL DEFAULT '',
            cues TEXT NOT NULL DEFAULT '',
            confidence REAL NOT NULL,
            status TEXT NOT NULL,
            evidence_count INTEGER NOT NULL DEFAULT 0,
            recall_count INTEGER NOT NULL DEFAULT 0,
            helpful_count INTEGER NOT NULL DEFAULT 0,
            not_applicable_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_recalled_at TEXT,
            superseded_by TEXT
        );

        CREATE TABLE IF NOT EXISTS memory_evidence (
            memory_id TEXT NOT NULL REFERENCES memories(id),
            episode_id TEXT NOT NULL REFERENCES episodes(id),
            PRIMARY KEY (memory_id, episode_id)
        );
        """
    )
    conn.execute(
        "INSERT OR REPLACE INTO meta(key, value) VALUES('schema_version', ?)",
        (str(SCHEMA_VERSION),),
    )
    conn.commit()


def sanitize_text(value: Any, *, limit: int = 2000) -> str:
    if value is None:
        return ""
    text = re.sub(r"\s+", " ", str(value)).strip()
    home = str(Path.home())
    if home and home != "/":
        text = text.replace(home, "~")
    text = re.sub(
        r"(?i)\b(api[_-]?key|access[_-]?token|secret|password)\s*[:=]\s*[^\s,;]+",
        r"\1=[REDACTED]",
        text,
    )
    return text[:limit]


def require_text(payload: dict[str, Any], key: str) -> str:
    value = sanitize_text(payload.get(key))
    if not value:
        raise MemoryError(f"缺少必填字段: {key}")
    return value


def normalize(value: str) -> str:
    return re.sub(r"[^a-z0-9\u4e00-\u9fff]+", "", value.lower())


def ngrams(value: str, size: int = 2) -> set[str]:
    value = normalize(value)
    if not value:
        return set()
    if len(value) <= size:
        return {value}
    return {value[index : index + size] for index in range(len(value) - size + 1)}


def similarity(left: str, right: str) -> float:
    left_norm = normalize(left)
    right_norm = normalize(right)
    if not left_norm or not right_norm:
        return 0.0
    left_grams = ngrams(left_norm)
    right_grams = ngrams(right_norm)
    union = left_grams | right_grams
    jaccard = len(left_grams & right_grams) / len(union) if union else 0.0
    sequence = SequenceMatcher(None, left_norm, right_norm).ratio()
    return 0.58 * jaccard + 0.42 * sequence


def load_payload(args: argparse.Namespace) -> dict[str, Any]:
    if args.stdin:
        try:
            payload = json.load(sys.stdin)
        except json.JSONDecodeError as exc:
            raise MemoryError(f"stdin 不是有效 JSON: {exc}") from exc
        if not isinstance(payload, dict):
            raise MemoryError("stdin JSON 必须是对象")
        return payload
    return {
        "skill": args.skill,
        "signal": args.signal,
        "disposition": args.disposition,
        "context_summary": args.context_summary,
        "failed_behavior": args.failed_behavior,
        "user_feedback": args.user_feedback,
        "corrected_behavior": args.corrected_behavior,
        "outcome": args.outcome,
        "evidence_ref": args.evidence_ref,
        "applies_when": args.applies_when,
        "lesson": args.lesson,
        "reason": args.reason,
        "boundaries": args.boundaries,
        "cues": args.cues,
        "merge_with": args.merge_with,
        "supersedes": args.supersedes,
    }


def row_to_memory(row: sqlite3.Row, *, score: float | None = None) -> dict[str, Any]:
    item = {
        "id": row["id"],
        "applies_when": row["applies_when"],
        "lesson": row["lesson"],
        "reason": row["reason"],
        "boundaries": row["boundaries"],
        "cues": row["cues"],
        "confidence": round(float(row["confidence"]), 3),
        "status": row["status"],
        "evidence_count": int(row["evidence_count"]),
        "recall_count": int(row["recall_count"]),
        "helpful_count": int(row["helpful_count"]),
        "not_applicable_count": int(row["not_applicable_count"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
        "last_recalled_at": row["last_recalled_at"],
        "superseded_by": row["superseded_by"],
    }
    if score is not None:
        item["relevance"] = round(score, 3)
    return item


def find_merge_candidate(
    conn: sqlite3.Connection, applies_when: str, lesson: str
) -> tuple[str | None, float]:
    incoming = f"{applies_when} {lesson}"
    best_id: str | None = None
    best_score = 0.0
    for row in conn.execute("SELECT * FROM memories WHERE status = ?", (ACTIVE,)):
        candidate = f"{row['applies_when']} {row['lesson']}"
        score = similarity(incoming, candidate)
        if score > best_score:
            best_id = str(row["id"])
            best_score = score
    return (best_id, best_score) if best_score >= 0.72 else (None, best_score)


def capture(args: argparse.Namespace) -> dict[str, Any]:
    payload = load_payload(args)
    skill = sanitize_text(payload.get("skill"), limit=100) or "unknown"
    signal = sanitize_text(payload.get("signal"), limit=100)
    if signal not in SIGNAL_CONFIDENCE:
        raise MemoryError(f"未知 signal: {signal or '<empty>'}")
    disposition = sanitize_text(payload.get("disposition"), limit=100) or "personal"
    if disposition not in {"personal", "execution_gap"}:
        raise MemoryError("disposition 只能是 personal 或 execution_gap")

    episode = {
        "id": new_id("episode"),
        "created_at": now_iso(),
        "skill": skill,
        "signal": signal,
        "disposition": disposition,
        "context_summary": sanitize_text(payload.get("context_summary")),
        "failed_behavior": sanitize_text(payload.get("failed_behavior")),
        "user_feedback": sanitize_text(payload.get("user_feedback")),
        "corrected_behavior": sanitize_text(payload.get("corrected_behavior")),
        "outcome": sanitize_text(payload.get("outcome")),
        "evidence_ref": sanitize_text(payload.get("evidence_ref"), limit=500),
    }

    path = db_path(args)
    conn = connect(path, create=True)
    assert conn is not None
    with conn:
        conn.execute(
            """
            INSERT INTO episodes(
                id, created_at, skill, signal, disposition, context_summary,
                failed_behavior, user_feedback, corrected_behavior, outcome,
                evidence_ref
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            tuple(episode.values()),
        )

        if disposition == "execution_gap":
            return {
                "ok": True,
                "action": "recorded_execution_gap",
                "episode_id": episode["id"],
                "memory_id": None,
                "database": str(path),
            }

        applies_when = require_text(payload, "applies_when")
        lesson = require_text(payload, "lesson")
        reason = sanitize_text(payload.get("reason"))
        boundaries = sanitize_text(payload.get("boundaries"))
        cues = sanitize_text(payload.get("cues"), limit=1000)
        merge_with = sanitize_text(payload.get("merge_with"), limit=100)
        supersedes = sanitize_text(payload.get("supersedes"), limit=100)

        if supersedes:
            existing = conn.execute(
                "SELECT id FROM memories WHERE id = ? AND status = ?",
                (supersedes, ACTIVE),
            ).fetchone()
            if existing is None:
                raise MemoryError(f"找不到可取代的有效经验: {supersedes}")

        if merge_with:
            existing = conn.execute(
                "SELECT * FROM memories WHERE id = ? AND status = ?",
                (merge_with, ACTIVE),
            ).fetchone()
            if existing is None:
                raise MemoryError(f"找不到可合并的有效经验: {merge_with}")
            merge_score = 1.0
        elif not supersedes:
            candidate_id, merge_score = find_merge_candidate(conn, applies_when, lesson)
            existing = (
                conn.execute("SELECT * FROM memories WHERE id = ?", (candidate_id,)).fetchone()
                if candidate_id
                else None
            )
        else:
            existing = None
            merge_score = 0.0

        base_confidence = SIGNAL_CONFIDENCE[signal]
        timestamp = now_iso()
        if existing is not None:
            memory_id = str(existing["id"])
            confidence = min(0.98, max(float(existing["confidence"]), base_confidence) + 0.06)
            prefer_incoming = signal == "explicit_generalization" and base_confidence >= float(
                existing["confidence"]
            )
            conn.execute(
                """
                UPDATE memories
                SET applies_when = ?, lesson = ?, reason = ?, boundaries = ?, cues = ?,
                    confidence = ?, evidence_count = evidence_count + 1, updated_at = ?
                WHERE id = ?
                """,
                (
                    applies_when if prefer_incoming else existing["applies_when"],
                    lesson if prefer_incoming else existing["lesson"],
                    reason or existing["reason"],
                    boundaries or existing["boundaries"],
                    cues or existing["cues"],
                    confidence,
                    timestamp,
                    memory_id,
                ),
            )
            action = "merged"
        else:
            memory_id = new_id("memory")
            conn.execute(
                """
                INSERT INTO memories(
                    id, applies_when, lesson, reason, boundaries, cues, confidence,
                    status, evidence_count, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
                """,
                (
                    memory_id,
                    applies_when,
                    lesson,
                    reason,
                    boundaries,
                    cues,
                    base_confidence,
                    ACTIVE,
                    timestamp,
                    timestamp,
                ),
            )
            action = "created"

        conn.execute(
            "INSERT INTO memory_evidence(memory_id, episode_id) VALUES (?, ?)",
            (memory_id, episode["id"]),
        )
        if supersedes:
            conn.execute(
                "UPDATE memories SET status = ?, superseded_by = ?, updated_at = ? WHERE id = ?",
                (SUPERSEDED, memory_id, timestamp, supersedes),
            )

    memory = conn.execute("SELECT * FROM memories WHERE id = ?", (memory_id,)).fetchone()
    assert memory is not None
    return {
        "ok": True,
        "action": action,
        "episode_id": episode["id"],
        "memory": row_to_memory(memory),
        "merge_similarity": round(merge_score, 3),
        "database": str(path),
    }


def context_pack_query(path: str | None) -> str:
    if not path:
        return ""
    source = Path(path).expanduser()
    try:
        payload = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return ""
    chunks = [str(payload.get("goal") or ""), str(payload.get("module") or "")]
    decisions = payload.get("decisions") if isinstance(payload.get("decisions"), dict) else {}
    for item in decisions.get("active", []) if isinstance(decisions.get("active"), list) else []:
        if not isinstance(item, dict):
            continue
        chunks.extend([str(item.get("title") or ""), str(item.get("summary") or "")[:500]])
    return " ".join(chunks)


def ranked_memories(
    conn: sqlite3.Connection, query: str, *, limit: int | None, minimum: float
) -> list[tuple[sqlite3.Row, float]]:
    ranked: list[tuple[sqlite3.Row, float]] = []
    for row in conn.execute("SELECT * FROM memories WHERE status = ?", (ACTIVE,)):
        candidate = " ".join(
            [row["applies_when"], row["lesson"], row["reason"], row["boundaries"], row["cues"]]
        )
        semantic = similarity(query, candidate)
        confidence = float(row["confidence"])
        score = semantic * 0.86 + confidence * 0.14
        if semantic >= minimum:
            ranked.append((row, score))
    ranked.sort(key=lambda item: (item[1], item[0]["updated_at"]), reverse=True)
    return ranked[:limit] if limit is not None else ranked


def recall_basis(row: sqlite3.Row) -> str:
    return " ".join([row["applies_when"], row["lesson"], row["boundaries"]])


def recall_context_cost(row: sqlite3.Row) -> int:
    # Markdown renderer only injects these three fields plus a small fixed prefix.
    return len(row["applies_when"]) + len(row["lesson"]) + len(row["boundaries"]) + 80


def select_recall_memories(
    ranked: list[tuple[sqlite3.Row, float]],
    *,
    context_budget: int,
    explicit_limit: int | None,
) -> tuple[list[tuple[sqlite3.Row, float]], dict[str, int | bool]]:
    selected: list[tuple[sqlite3.Row, float]] = []
    selected_basis: list[str] = []
    used_chars = 0
    duplicate_count = 0
    budget_count = 0
    explicit_limit_count = 0

    for row, score in ranked:
        basis = recall_basis(row)
        if any(similarity(basis, existing) >= RECALL_DUPLICATE_THRESHOLD for existing in selected_basis):
            duplicate_count += 1
            continue
        if explicit_limit is not None and len(selected) >= explicit_limit:
            explicit_limit_count += 1
            continue
        cost = recall_context_cost(row)
        if used_chars + cost > context_budget:
            budget_count += 1
            continue
        selected.append((row, score))
        selected_basis.append(basis)
        used_chars += cost

    return selected, {
        "candidate_count": len(ranked),
        "selected_count": len(selected),
        "used_context_chars": used_chars,
        "context_budget_chars": context_budget,
        "omitted_duplicate_count": duplicate_count,
        "omitted_budget_count": budget_count,
        "omitted_explicit_limit_count": explicit_limit_count,
        "truncated_by_budget": budget_count > 0,
    }


def recall(args: argparse.Namespace) -> dict[str, Any]:
    path = db_path(args)
    conn = connect(path, create=False)
    if conn is None:
        return {"ok": True, "advisory": True, "memories": [], "database": str(path)}
    query = sanitize_text(f"{args.query or ''} {context_pack_query(args.context_pack)}", limit=10000)
    if not query:
        raise MemoryError("recall 需要 --query 或 --context-pack")
    explicit_limit = int(args.limit) if args.limit is not None else None
    if explicit_limit is not None and explicit_limit < 1:
        raise MemoryError("--limit 必须大于 0")
    context_budget = int(args.max_context_chars)
    if context_budget < 1:
        raise MemoryError("--max-context-chars 必须大于 0")

    all_ranked = ranked_memories(conn, query, limit=None, minimum=float(args.minimum_relevance))
    safety_omitted = max(0, len(all_ranked) - SAFETY_MAX_CANDIDATES)
    selected, selection = select_recall_memories(
        all_ranked[:SAFETY_MAX_CANDIDATES],
        context_budget=context_budget,
        explicit_limit=explicit_limit,
    )
    selection["eligible_count"] = len(all_ranked)
    selection["omitted_safety_count"] = safety_omitted
    timestamp = now_iso()
    if not args.no_mark and selected:
        with conn:
            for row, _ in selected:
                conn.execute(
                    """
                    UPDATE memories
                    SET recall_count = recall_count + 1, last_recalled_at = ?, updated_at = updated_at
                    WHERE id = ?
                    """,
                    (timestamp, row["id"]),
                )
    return {
        "ok": True,
        "advisory": True,
        "authority": "personal experience cannot override current project truth or skill rules",
        "query": query,
        "selection": selection,
        "memories": [row_to_memory(row, score=score) for row, score in selected],
        "database": str(path),
    }


def feedback(args: argparse.Namespace) -> dict[str, Any]:
    path = db_path(args)
    conn = connect(path, create=False)
    if conn is None:
        raise MemoryError("个人经验库尚不存在")
    row = conn.execute("SELECT * FROM memories WHERE id = ?", (args.memory_id,)).fetchone()
    if row is None or row["status"] != ACTIVE:
        raise MemoryError(f"找不到有效经验: {args.memory_id}")
    confidence = float(row["confidence"])
    helpful = int(row["helpful_count"])
    not_applicable = int(row["not_applicable_count"])
    if args.result == "helpful":
        confidence = min(0.98, confidence + 0.03)
        helpful += 1
    elif args.result == "audit_pass":
        confidence = min(0.98, confidence + 0.07)
        helpful += 1
    elif args.result == "not_applicable":
        confidence = max(0.05, confidence - 0.08)
        not_applicable += 1
    elif args.result == "corrected":
        confidence = max(0.05, confidence - 0.20)
        not_applicable += 1
    timestamp = now_iso()
    with conn:
        conn.execute(
            """
            UPDATE memories
            SET confidence = ?, helpful_count = ?, not_applicable_count = ?, updated_at = ?
            WHERE id = ?
            """,
            (confidence, helpful, not_applicable, timestamp, args.memory_id),
        )
    updated = conn.execute("SELECT * FROM memories WHERE id = ?", (args.memory_id,)).fetchone()
    assert updated is not None
    return {"ok": True, "result": args.result, "memory": row_to_memory(updated)}


def status(args: argparse.Namespace) -> dict[str, Any]:
    path = db_path(args)
    conn = connect(path, create=False)
    if conn is None:
        return {
            "ok": True,
            "exists": False,
            "database": str(path),
            "memories": {ACTIVE: 0, SUPERSEDED: 0, FORGOTTEN: 0},
            "episodes": 0,
        }
    counts = {ACTIVE: 0, SUPERSEDED: 0, FORGOTTEN: 0}
    for row in conn.execute("SELECT status, COUNT(*) AS count FROM memories GROUP BY status"):
        counts[str(row["status"])] = int(row["count"])
    episodes = int(conn.execute("SELECT COUNT(*) FROM episodes").fetchone()[0])
    return {
        "ok": True,
        "exists": True,
        "database": str(path),
        "schema_version": SCHEMA_VERSION,
        "memories": counts,
        "episodes": episodes,
    }


def search(args: argparse.Namespace) -> dict[str, Any]:
    path = db_path(args)
    conn = connect(path, create=False)
    if conn is None:
        return {"ok": True, "memories": [], "database": str(path)}
    ranked = ranked_memories(
        conn,
        sanitize_text(args.query, limit=10000),
        limit=max(1, min(int(args.limit), 100)),
        minimum=0.0,
    )
    return {
        "ok": True,
        "memories": [row_to_memory(row, score=score) for row, score in ranked],
        "database": str(path),
    }


def show(args: argparse.Namespace) -> dict[str, Any]:
    path = db_path(args)
    conn = connect(path, create=False)
    if conn is None:
        raise MemoryError("个人经验库尚不存在")
    row = conn.execute("SELECT * FROM memories WHERE id = ?", (args.memory_id,)).fetchone()
    if row is None:
        raise MemoryError(f"找不到经验: {args.memory_id}")
    evidence = [
        dict(item)
        for item in conn.execute(
            """
            SELECT episodes.* FROM episodes
            JOIN memory_evidence ON memory_evidence.episode_id = episodes.id
            WHERE memory_evidence.memory_id = ?
            ORDER BY episodes.created_at
            """,
            (args.memory_id,),
        )
    ]
    return {"ok": True, "memory": row_to_memory(row), "evidence": evidence}


def forget(args: argparse.Namespace) -> dict[str, Any]:
    path = db_path(args)
    conn = connect(path, create=False)
    if conn is None:
        raise MemoryError("个人经验库尚不存在")
    row = conn.execute("SELECT id FROM memories WHERE id = ?", (args.memory_id,)).fetchone()
    if row is None:
        raise MemoryError(f"找不到经验: {args.memory_id}")
    with conn:
        conn.execute(
            "UPDATE memories SET status = ?, updated_at = ? WHERE id = ?",
            (FORGOTTEN, now_iso(), args.memory_id),
        )
    return {"ok": True, "forgotten": args.memory_id}


def export_all(args: argparse.Namespace) -> dict[str, Any]:
    path = db_path(args)
    conn = connect(path, create=False)
    if conn is None:
        return {"schema_version": SCHEMA_VERSION, "memories": [], "episodes": []}
    return {
        "schema_version": SCHEMA_VERSION,
        "exported_at": now_iso(),
        "memories": [row_to_memory(row) for row in conn.execute("SELECT * FROM memories")],
        "episodes": [dict(row) for row in conn.execute("SELECT * FROM episodes")],
    }


def render_markdown(payload: dict[str, Any], command: str) -> str:
    if command == "recall":
        memories = payload.get("memories", [])
        if not memories:
            return ""
        lines = ["个人经验提醒（只作后台检查，不是项目事实或决定）："]
        for item in memories:
            line = f"- [{item['id']}] 当{item['applies_when']}，{item['lesson']}"
            if item.get("boundaries"):
                line += f"；不适用边界：{item['boundaries']}"
            lines.append(line)
        selection = payload.get("selection", {})
        omitted = int(selection.get("omitted_budget_count", 0)) + int(
            selection.get("omitted_safety_count", 0)
        )
        if omitted:
            lines.append(
                f"召回说明：另有 {omitted} 条候选因上下文预算或异常保护未注入；"
                "应优先合并碎片经验，不要机械扩大条数。"
            )
        return "\n".join(lines)
    if command == "status":
        memories = payload["memories"]
        return (
            f"个人经验库：{'已建立' if payload['exists'] else '尚未建立'}\n"
            f"有效 {memories.get(ACTIVE, 0)}，已取代 {memories.get(SUPERSEDED, 0)}，"
            f"已遗忘 {memories.get(FORGOTTEN, 0)}，证据记录 {payload['episodes']}"
        )
    if command in {"search", "show"}:
        memories: Iterable[dict[str, Any]]
        memories = payload.get("memories") or ([payload["memory"]] if payload.get("memory") else [])
        return "\n".join(
            f"- {item['id']} [{item['status']}] {item['applies_when']} → {item['lesson']}"
            for item in memories
        )
    return json.dumps(payload, ensure_ascii=False, indent=2)


def add_capture_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--stdin", action="store_true", help="从 stdin 读取 JSON payload")
    parser.add_argument("--skill", default="design")
    parser.add_argument("--signal", choices=sorted(SIGNAL_CONFIDENCE), default="explicit_correction")
    parser.add_argument("--disposition", choices=("personal", "execution_gap"), default="personal")
    parser.add_argument("--context-summary", default="")
    parser.add_argument("--failed-behavior", default="")
    parser.add_argument("--user-feedback", default="")
    parser.add_argument("--corrected-behavior", default="")
    parser.add_argument("--outcome", default="")
    parser.add_argument("--evidence-ref", default="")
    parser.add_argument("--applies-when", default="")
    parser.add_argument("--lesson", default="")
    parser.add_argument("--reason", default="")
    parser.add_argument("--boundaries", default="")
    parser.add_argument("--cues", default="")
    parser.add_argument("--merge-with", default="")
    parser.add_argument("--supersedes", default="")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-home", help="覆盖 PMAI_STATE_HOME，默认 ~/.pmai-state")
    subparsers = parser.add_subparsers(dest="command", required=True)

    capture_parser = subparsers.add_parser("capture", help="记录纠偏证据并创建或更新个人经验")
    capture_parser.add_argument("--format", choices=("json", "markdown"), default="json")
    add_capture_arguments(capture_parser)

    recall_parser = subparsers.add_parser("recall", help="按当前任务召回并自适应筛选个人经验")
    recall_parser.add_argument("--format", choices=("json", "markdown"), default="json")
    recall_parser.add_argument("--query", default="")
    recall_parser.add_argument("--context-pack")
    recall_parser.add_argument(
        "--limit", type=int, help="显式诊断上限；正常 design 不传，避免固定条数裁剪"
    )
    recall_parser.add_argument(
        "--max-context-chars",
        type=int,
        default=DEFAULT_CONTEXT_BUDGET,
        help="召回内容字符预算，默认 8000；只作上下文保护",
    )
    recall_parser.add_argument("--minimum-relevance", type=float, default=0.04)
    recall_parser.add_argument("--no-mark", action="store_true")

    feedback_parser = subparsers.add_parser("feedback", help="记录一次个人经验使用结果")
    feedback_parser.add_argument("--format", choices=("json", "markdown"), default="json")
    feedback_parser.add_argument("memory_id")
    feedback_parser.add_argument(
        "--result", choices=("helpful", "audit_pass", "not_applicable", "corrected"), required=True
    )

    status_parser = subparsers.add_parser("status", help="显示个人经验库状态")
    status_parser.add_argument("--format", choices=("json", "markdown"), default="json")

    search_parser = subparsers.add_parser("search", help="搜索个人经验")
    search_parser.add_argument("--format", choices=("json", "markdown"), default="json")
    search_parser.add_argument("query")
    search_parser.add_argument("--limit", type=int, default=20)

    show_parser = subparsers.add_parser("show", help="查看个人经验及证据")
    show_parser.add_argument("--format", choices=("json", "markdown"), default="json")
    show_parser.add_argument("memory_id")

    forget_parser = subparsers.add_parser("forget", help="让一条个人经验退出召回")
    forget_parser.add_argument("--format", choices=("json", "markdown"), default="json")
    forget_parser.add_argument("memory_id")

    export_parser = subparsers.add_parser("export", help="导出个人经验与精简证据 JSON")
    export_parser.add_argument("--format", choices=("json", "markdown"), default="json")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        if args.command == "capture":
            payload = capture(args)
        elif args.command == "recall":
            payload = recall(args)
        elif args.command == "feedback":
            payload = feedback(args)
        elif args.command == "status":
            payload = status(args)
        elif args.command == "search":
            payload = search(args)
        elif args.command == "show":
            payload = show(args)
        elif args.command == "forget":
            payload = forget(args)
        elif args.command == "export":
            payload = export_all(args)
        else:
            parser.error(f"unknown command: {args.command}")
            return 2
    except MemoryError as exc:
        print(f"personal-memory: {exc}", file=sys.stderr)
        return 2
    except sqlite3.Error as exc:
        print(f"personal-memory: 数据库错误: {exc}", file=sys.stderr)
        return 2

    if args.format == "markdown":
        print(render_markdown(payload, args.command))
    else:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
