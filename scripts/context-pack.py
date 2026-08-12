#!/usr/bin/env python3
"""Compile the deterministic PMAI context pack used across one work lifecycle.

The pack is an internal cache, never a new product truth source.  It points back
to the existing project spine, module triplet, decision archive, mockups and
implementation files, and binds the assembled view to content hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from _lib.decision_status import decision_is_question, decision_is_superseded
from _lib.project_definition import ProjectDefinitionError, load_project_definition
from _lib.open_questions import parse_current_open_questions
from _lib.proposal import (
    contract_path as proposal_contract_path,
    proposal_state,
    resolve_proposal_path,
)
from _lib.legacy_recovery import validate_legacy_recovery
from _lib.work_contract import normalize_work_state


ROOT_SOURCES = (
    ("PRODUCT.md", "product_definition"),
    ("PRODUCT-STATE.md", "current_product_state"),
    ("PRODUCT-RULES.md", "active_product_rules"),
    ("DESIGN.md", "current_design_baseline"),
    ("TODO.md", "open_product_work"),
    ("docs/modules/INDEX.md", "module_index"),
)
CURRENT_SOURCE_HASH_VERSION = 2
CONTEXT_ONLY_HASH_ROLES = {
    "current_product_state",
    "open_product_work",
    "module_index",
    "work_state",
}
MODULE_SOURCES = (
    ("discussion.md", "discussion"),
    ("decisions.md", "module_decisions"),
    ("spec.md", "module_spec"),
    (".work-meta.json", "work_state"),
)
GENERIC_HEADINGS = {
    "已拍板决策",
    "共同理由",
    "否过的方案",
    "待复核决策",
    "规则清单",
    "参考材料",
    "变更日志",
    "变更记录",
    "版本信息",
    "名词解释",
    "讨论记录",
    "未决问题",
    "待确认问题",
}
SUPERSEDED_SECTION_HEADINGS = {"被取代的决定"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_bytes(path: Path) -> bytes:
    try:
        return path.read_bytes()
    except OSError as exc:
        raise SystemExit(f"无法读取上下文文件 {path}: {exc}") from exc


def git_output(repo_root: Path, *args: str) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(repo_root), *args],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def repo_relative(repo_root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        raise SystemExit(f"上下文文件不在仓库内: {path}")


def resolve_module(repo_root: Path, value: str | None) -> Path | None:
    modules_root = repo_root / "docs" / "modules"
    if value:
        candidate = Path(value).expanduser()
        if not candidate.is_absolute():
            direct = repo_root / candidate
            candidate = direct if direct.exists() else modules_root / value
        if candidate.is_file():
            candidate = candidate.parent
        return candidate.resolve()

    active: list[Path] = []
    if modules_root.is_dir():
        for meta in modules_root.glob("*/.work-meta.json"):
            try:
                data = json.loads(meta.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if data.get("status") == "active":
                active.append(meta.parent)
    return active[0].resolve() if len(active) == 1 else None


def load_work_meta(module_dir: Path | None) -> dict:
    if module_dir is None:
        return {}
    path = module_dir / ".work-meta.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


@dataclass(frozen=True)
class Source:
    path: Path
    role: str


def collect_sources(
    repo_root: Path,
    module_dir: Path | None,
    meta: dict,
    current_proposal: dict | None,
) -> list[Source]:
    sources: list[Source] = []
    for rel, role in ROOT_SOURCES:
        path = repo_root / rel
        if path.is_file():
            sources.append(Source(path, role))
    project_definition = repo_root / ".pm-workflow" / "project.yml"
    if project_definition.is_file():
        sources.append(Source(project_definition, "project_definition"))
    if current_proposal is not None:
        sources.append(Source(proposal_contract_path(repo_root), "proposal_contract"))
        sources.append(
            Source(
                resolve_proposal_path(repo_root, current_proposal["path"]),
                "product_proposal",
            )
        )
    if module_dir is not None:
        for name, role in MODULE_SOURCES:
            path = module_dir / name
            if path.is_file():
                sources.append(Source(path, role))
    archive = repo_root / "docs" / "decisions"
    if archive.is_dir():
        sources.extend(Source(path, "frozen_project_decision") for path in sorted(archive.glob("*.md")))
    manifest = repo_root / "mockups" / "manifest.json"
    if manifest.is_file():
        sources.append(Source(manifest, "mockup_manifest"))
    attachments = meta.get("attachments_seen", [])
    if isinstance(attachments, list):
        for item in attachments:
            if not isinstance(item, dict) or not isinstance(item.get("name"), str):
                continue
            path = (repo_root / item["name"]).resolve()
            try:
                path.relative_to(repo_root)
            except ValueError:
                continue
            if path.is_file():
                sources.append(Source(path, "input_evidence"))
    return sources


def split_markdown_sections(text: str) -> list[tuple[str, str]]:
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
    matches = list(re.finditer(r"^(#{2,4})\s+(.+?)\s*$", text, re.MULTILINE))
    sections: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        sections.append((match.group(2).strip(), text[start:end].strip()))
    return sections


def normalize_title(title: str) -> str:
    title = re.sub(r"^D\d+[.：:\s-]*", "", title, flags=re.IGNORECASE)
    title = re.sub(r"[`*_~]", "", title)
    return re.sub(r"\s+", "", title).lower()


def heading_label(title: str) -> str:
    value = re.sub(r"[`*_~]", "", title).strip()
    return re.sub(r"^\d+[.、：:\s-]*", "", value).strip()


def is_module_decision_heading(title: str) -> bool:
    value = re.sub(r"[`*_~]", "", title).strip()
    return re.match(r"^D\d+(?:[.、：:\s-]|$)", value, re.IGNORECASE) is not None


def decision_status(title: str, body: str, role: str) -> str:
    if role == "frozen_project_decision":
        return "frozen"
    return "superseded" if decision_is_superseded(title, body) else "active"


def parse_decisions(repo_root: Path, sources: Iterable[Source]) -> tuple[list[dict], list[dict]]:
    decisions: list[dict] = []
    question_like: list[dict] = []
    decision_roles = {"module_decisions", "active_product_rules", "frozen_project_decision"}
    for source in sources:
        if source.role not in decision_roles or source.path.suffix.lower() != ".md":
            continue
        text = source.path.read_text(encoding="utf-8")
        sections = split_markdown_sections(text)
        if not sections and source.role == "frozen_project_decision":
            sections = [(source.path.stem, text)]
        for title, body in sections:
            cleaned = normalize_title(title)
            label = heading_label(title)
            if not cleaned or label in GENERIC_HEADINGS or not body:
                continue
            if source.role == "module_decisions" and not is_module_decision_heading(title):
                if label not in SUPERSEDED_SECTION_HEADINGS:
                    continue
            if source.role == "active_product_rules" and label == "规则清单":
                continue
            item = {
                "id": sha256_bytes(f"{source.path}:{title}".encode("utf-8"))[:12],
                "title": title,
                "status": decision_status(title, body, source.role),
                "scope": "module" if source.role == "module_decisions" else "project",
                "source": repo_relative(repo_root, source.path),
                "summary": re.sub(r"\s+", " ", body)[:500],
                "normalized_title": cleaned,
            }
            if decision_is_question(title, body):
                item["reason"] = "question_text_is_not_a_decision"
                question_like.append(item)
                continue
            decisions.append(item)
    return decisions, question_like


def find_conflicts(decisions: list[dict]) -> list[dict]:
    active_by_title: dict[str, list[dict]] = {}
    for item in decisions:
        if item["status"] != "active":
            continue
        active_by_title.setdefault(item["normalized_title"], []).append(item)
    conflicts = []
    for title, items in active_by_title.items():
        summaries = {item["summary"] for item in items}
        if title and len(items) > 1 and len(summaries) > 1:
            conflicts.append(
                {
                    "normalized_title": title,
                    "decision_ids": [item["id"] for item in items],
                    "sources": [item["source"] for item in items],
                }
            )
    return conflicts


def unresolved_questions(repo_root: Path, module_dir: Path | None) -> list[dict]:
    if module_dir is None:
        return []
    path = module_dir / "discussion.md"
    if not path.is_file():
        return []
    section = parse_current_open_questions(path.read_text(encoding="utf-8"))
    if section is None:
        return []
    source = repo_relative(repo_root, path)
    return [
        {
            "source": source,
            "line": question.question_line,
            "text": question.text,
        }
        for question in section.unresolved
    ]


def extract_keywords(module_dir: Path | None, goal: str | None) -> list[str]:
    raw = [goal or "", module_dir.name if module_dir else ""]
    tokens: list[str] = []
    for value in raw:
        tokens.extend(re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}|[\u4e00-\u9fff]{2,8}", value))
    seen: set[str] = set()
    return [token for token in tokens if not (token in seen or seen.add(token))][:12]


def relevant_implementation_paths(repo_root: Path, keywords: list[str], meta: dict) -> list[str]:
    paths: set[str] = set()
    build = meta.get("build") if isinstance(meta.get("build"), dict) else {}
    target = build.get("target") if isinstance(build.get("target"), dict) else {}
    for value in target.get("paths", []) if isinstance(target.get("paths"), list) else []:
        if isinstance(value, str):
            paths.add(value)
    tracked = git_output(repo_root, "ls-files").splitlines()
    definition_path = repo_root / ".pm-workflow" / "project.yml"
    if definition_path.exists():
        try:
            definition = load_project_definition(definition_path)
        except ProjectDefinitionError as exc:
            raise SystemExit(str(exc)) from exc
        roots = tuple(path.rstrip("/") + "/" for path in definition["implementation"]["entrypoints"])
    else:
        # Before the first buildable design, or for legacy consumers, scan the
        # conventional code roots as read-only context. This does not define a
        # new project's build shape.
        roots = ("prototype/", "src/", "app/", "apps/", "packages/", "Sources/")
    for rel in tracked:
        lowered = rel.lower()
        if not rel.startswith(roots):
            continue
        if not keywords or any(keyword.lower() in lowered for keyword in keywords):
            paths.add(rel)
        if len(paths) >= 100:
            break
    return sorted(paths)


def source_hash_version(meta: dict) -> int:
    build = meta.get("build") if isinstance(meta.get("build"), dict) else {}
    raw = build.get("source_hash_version") or meta.get("source_hash_version")
    if raw is not None:
        try:
            version = int(raw)
        except (TypeError, ValueError) as exc:
            raise SystemExit(f"source_hash_version 必须是整数: {raw}") from exc
        if version not in {1, CURRENT_SOURCE_HASH_VERSION}:
            raise SystemExit(f"不支持的 source_hash_version: {version}")
        return version
    # Existing approved work predates scoped currentness and must continue to
    # compile with the original full-document hash until that round closes.
    if build.get("approved_source_hash") or meta.get("approved_source_hash"):
        return 1
    return CURRENT_SOURCE_HASH_VERSION


def source_records(
    repo_root: Path, sources: list[Source], hash_version: int
) -> tuple[list[dict], dict[str, str], str, list[str]]:
    records = []
    hashes: dict[str, str] = {}
    digest = hashlib.sha256()
    hash_scope: list[str] = []
    for source in sorted(sources, key=lambda item: repo_relative(repo_root, item.path)):
        rel = repo_relative(repo_root, source.path)
        data = read_bytes(source.path)
        file_hash = sha256_bytes(data)
        hashes[rel] = file_hash
        excluded_roles = {"work_state"} if hash_version == 1 else CONTEXT_ONLY_HASH_ROLES
        # Context-only sources remain readable and individually hashed in the
        # pack, but do not invalidate a v2 design on coordination-only changes.
        if source.role not in excluded_roles:
            hash_scope.append(rel)
            digest.update(rel.encode("utf-8"))
            digest.update(b"\0")
            digest.update(file_hash.encode("ascii"))
            digest.update(b"\0")
        text = data.decode("utf-8", errors="replace")
        records.append(
            {
                "path": rel,
                "role": source.role,
                "sha256": file_hash,
                "bytes": len(data),
                "excerpt": text[:4000],
            }
        )
    return records, hashes, digest.hexdigest(), hash_scope


def validate_design_recovery_checkpoint(repo_root: Path, recovery: dict) -> None:
    """Keep the recovery checkpoint on the current history without freezing design edits."""

    if recovery.get("kind") != "active-design":
        return
    checkpoint = str(recovery.get("checkpoint_commit") or "").strip()
    ancestry = subprocess.run(
        ["git", "-C", str(repo_root), "merge-base", "--is-ancestor", checkpoint, "HEAD"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    if ancestry.returncode == 1:
        raise SystemExit("legacy recovery checkpoint 不在当前主线历史中；请重新确认。")
    if ancestry.returncode != 0:
        detail = ancestry.stderr.decode("utf-8", errors="replace").strip()
        raise SystemExit(detail or "无法验证 legacy recovery checkpoint。")


def build_pack(args: argparse.Namespace) -> dict:
    repo_root = Path(args.repo_root).expanduser().resolve()
    if not repo_root.is_dir():
        raise SystemExit(f"仓库不存在: {repo_root}")
    module_dir = resolve_module(repo_root, args.module)
    if module_dir is not None:
        repo_relative(repo_root, module_dir)
    meta = load_work_meta(module_dir)
    build = meta.get("build") if isinstance(meta.get("build"), dict) else {}
    approved_target = meta.get("approved_target") if isinstance(meta.get("approved_target"), dict) else {}
    target = build.get("target") if isinstance(build.get("target"), dict) else approved_target
    definition_path = repo_root / ".pm-workflow" / "project.yml"
    if definition_path.exists():
        try:
            project_definition = load_project_definition(definition_path)
        except ProjectDefinitionError as exc:
            raise SystemExit(str(exc)) from exc
        target_kind = project_definition["project"]["type"]
        target_entrypoints = project_definition["implementation"]["entrypoints"]
    else:
        target_kind = target.get("kind")
        target_entrypoints = target.get("entrypoints", [])
    current_proposal = None
    try:
        legacy_recovery = validate_legacy_recovery(meta)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    proposal_gate = proposal_state(repo_root)
    if proposal_gate["state"] == "accepted":
        current_proposal = proposal_gate["proposal"]
    elif proposal_gate["state"] == "invalid":
        raise SystemExit(str(proposal_gate.get("reason") or "当前 Product Proposal 无效。"))
    elif proposal_gate["state"] == "required":
        # A previously accepted v1-v4 active build may carry an explicit PM
        # recovery checkpoint.  That checkpoint is the narrow compatibility
        # boundary; new work and v5 work still require the current Proposal
        # gate exactly as before.
        if legacy_recovery:
            proposal_gate = {"state": "legacy_recovered"}
        else:
            gaps = proposal_gate.get("gaps") or []
            gap_text = "缺少：" + "、".join(str(item) for item in gaps) + "。" if gaps else ""
            raise SystemExit(
                "当前项目还没有完整 Product Proposal 或等价产品基线；"
                f"{gap_text}请先运行 /pmai-proposal，确认产品方向后再进入 design。"
            )
    sources = collect_sources(repo_root, module_dir, meta, current_proposal)
    hash_version = source_hash_version(meta)
    records, input_hashes, source_hash, hash_scope = source_records(
        repo_root, sources, hash_version
    )
    if legacy_recovery:
        validate_design_recovery_checkpoint(repo_root, legacy_recovery)
    decisions, question_like = parse_decisions(repo_root, sources)
    keywords = extract_keywords(module_dir, args.goal)
    return {
        "schema_version": 1,
        "source_hash_version": hash_version,
        "compiled_at": now_iso(),
        "repo": {
            "head": git_output(repo_root, "rev-parse", "HEAD"),
            "branch": git_output(repo_root, "branch", "--show-current"),
        },
        "goal": args.goal,
        "module": repo_relative(repo_root, module_dir) if module_dir else None,
        "target": {
            "kind": target_kind,
            "paths": target.get("paths", []),
            "entrypoints": target_entrypoints,
        },
        "lifecycle_state": (
            normalize_work_state(meta).lifecycle_state if meta else "designing"
        ),
        "design_revision": int(build.get("design_revision") or meta.get("design_revision") or 1),
        "approved_source_hash": build.get("approved_source_hash") or meta.get("approved_source_hash"),
        "source_hash": source_hash,
        "source_hash_scope": hash_scope,
        "product_proposal": current_proposal,
        "legacy_recovery": legacy_recovery,
        "implementation_commit": build.get("implementation_commit") or git_output(repo_root, "rev-parse", "HEAD"),
        "sources": records,
        "input_hashes": input_hashes,
        "decisions": {
            "active": [item for item in decisions if item["status"] == "active"],
            "superseded": [item for item in decisions if item["status"] == "superseded"],
            "frozen": [item for item in decisions if item["status"] == "frozen"],
            "question_like_rejected": question_like,
            "possible_conflicts": find_conflicts(decisions),
        },
        "unresolved_questions": unresolved_questions(repo_root, module_dir),
        "accepted_deltas": build.get("accepted_deltas", []),
        "relevant_implementation_paths": relevant_implementation_paths(repo_root, keywords, meta),
    }


def write_output(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp.replace(path)


def ensure_context_cache_ignored(repo_root: Path, output_path: Path) -> None:
    """Keep runtime context cache out of Git for both new and legacy consumers.

    New projects already receive the tracked `.gitignore` rule.  Older projects
    are repaired locally through `.git/info/exclude`, avoiding an unrelated
    tracked-file edit during design.
    """
    cache_root = (repo_root / ".pm-workflow" / "context").resolve()
    try:
        output_path.expanduser().resolve().relative_to(cache_root)
    except ValueError:
        return

    probe = ".pm-workflow/context/.pmai-ignore-probe"
    ignored = subprocess.run(
        ["git", "-C", str(repo_root), "check-ignore", "-q", "--", probe],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if ignored.returncode == 0:
        return

    git_path = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "--git-path", "info/exclude"],
        text=True,
        capture_output=True,
        check=False,
    )
    if git_path.returncode != 0 or not git_path.stdout.strip():
        return
    exclude_path = Path(git_path.stdout.strip())
    if not exclude_path.is_absolute():
        exclude_path = repo_root / exclude_path
    try:
        exclude_path.parent.mkdir(parents=True, exist_ok=True)
        existing = exclude_path.read_text(encoding="utf-8") if exclude_path.exists() else ""
        rule = ".pm-workflow/context/"
        if rule not in {line.strip() for line in existing.splitlines()}:
            prefix = "" if not existing or existing.endswith("\n") else "\n"
            exclude_path.write_text(existing + prefix + rule + "\n", encoding="utf-8")
    except OSError as exc:
        print(f"warning: 无法自动排除 context cache：{exc}", file=sys.stderr)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo-root", default=".")
    result.add_argument("--module", help="模块名或 docs/modules/<模块> 路径；省略时自动选择唯一 active work")
    result.add_argument("--goal")
    result.add_argument("--output", help="内部 JSON 输出路径；省略时写 stdout")
    return result


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    payload = build_pack(args)
    if args.output:
        repo_root = Path(args.repo_root).expanduser().resolve()
        output_path = Path(args.output).expanduser()
        ensure_context_cache_ignored(repo_root, output_path)
        write_output(output_path, payload)
        print(args.output)
    else:
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
