#!/usr/bin/env python3
"""Reconcile explicitly declared business terms and roles after landing.

Candidates only come from durable, structured product evidence:

- terminology and user-role tables in the active module/spec documents;
- explicit ``术语：...`` / ``角色：...`` declarations in ``decisions.md``;
- legacy accepted deltas whose kind is ``term`` or ``role``;
- scoped accepted deltas with explicit ``affects`` term / role names.

The detector deliberately does not infer terminology from quotes, bold text, or
implementation files. Its output feeds the post-land documentation impact map;
it never edits PRODUCT.md itself.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path


_SCRIPTS_DIR = str(Path(__file__).resolve().parent.parent)
if _SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, _SCRIPTS_DIR)

from _lib.decision_status import (  # noqa: E402
    decision_is_question,
    decision_is_superseded,
    is_state_question,
)


MINIMAL_WHITELIST = {"用户", "产品", "数据", "API", "JSON"}
TERM_KINDS = {"term"}
ROLE_KINDS = {"role"}
EMPTY_VALUES = {"", "-", "/", "无", "暂无", "待定", "待补充", "术语", "术语 / 缩略词", "角色", "角色名"}


def framework_root() -> Path:
    """Resolve framework assets from PMAI_HOME or this installed script."""
    candidates: list[Path] = []
    configured = os.environ.get("PMAI_HOME")
    if configured:
        candidates.append(Path(configured).expanduser())
    candidates.append(Path(__file__).resolve().parents[2])
    for candidate in candidates:
        if (candidate / "skills" / "_shared" / "term-detector" / "whitelist.json").is_file():
            return candidate
    return candidates[-1]


def load_whitelist() -> set[str]:
    path = framework_root() / "skills" / "_shared" / "term-detector" / "whitelist.json"
    if not path.is_file():
        return set(MINIMAL_WHITELIST)
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set(MINIMAL_WHITELIST)
    terms: set[str] = set()
    if isinstance(data, dict):
        for values in data.values():
            if isinstance(values, list):
                terms.update(str(value).strip() for value in values if str(value).strip())
    return terms or set(MINIMAL_WHITELIST)


def strip_markup(value: str) -> str:
    value = re.sub(r"<!--.*?-->", "", value, flags=re.DOTALL)
    value = re.sub(r"[`*_~]", "", value)
    value = re.sub(r"<br\s*/?>", " ", value, flags=re.IGNORECASE)
    value = value.strip().strip('"“”「」『』')
    return re.sub(r"\s+", " ", value).strip()


def valid_name(value: str) -> bool:
    if value in EMPTY_VALUES or len(value) > 64:
        return False
    return not bool(re.search(r"[。！？!?；;\n]", value))


def split_sections(text: str) -> list[tuple[str, str]]:
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
    matches = list(re.finditer(r"^(#{1,6})\s+(.+?)\s*$", text, re.MULTILINE))
    result: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        result.append((match.group(2).strip(), text[match.end() : end].strip()))
    return result


def normalized_heading(value: str) -> str:
    value = re.sub(r"^[一二三四五六七八九十0-9.、：:\s-]+", "", strip_markup(value))
    return re.sub(r"\s+", "", value)


def split_table_row(line: str) -> list[str]:
    value = line.strip()
    if value.startswith("|"):
        value = value[1:]
    if value.endswith("|"):
        value = value[:-1]
    return [strip_markup(cell.replace(r"\|", "|")) for cell in re.split(r"(?<!\\)\|", value)]


def is_separator_row(line: str) -> bool:
    cells = split_table_row(line)
    return bool(cells) and all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells)


def is_table_data_row(line: str) -> bool:
    """Accept pipe rows until the next Markdown block starts."""
    if "|" not in line or not line.strip():
        return False
    if line.startswith(("    ", "\t")):
        return False
    stripped = line.lstrip()
    return re.match(
        r"^(?:#{1,6}(?:\s|$)|>|`{3,}|~{3,}|(?:[-+*]|\d{1,9}[.)])(?:\s|$))",
        stripped,
    ) is None


def tables(body: str) -> list[tuple[list[str], list[list[str]]]]:
    lines = body.splitlines()
    result: list[tuple[list[str], list[list[str]]]] = []
    index = 0
    while index + 1 < len(lines):
        if "|" not in lines[index] or not is_separator_row(lines[index + 1]):
            index += 1
            continue
        header = split_table_row(lines[index])
        rows: list[list[str]] = []
        index += 2
        while index < len(lines) and is_table_data_row(lines[index]):
            rows.append(split_table_row(lines[index]))
            index += 1
        result.append((header, rows))
    return result


def repo_relative(repo_root: Path, path: Path) -> str:
    return path.resolve().relative_to(repo_root.resolve()).as_posix()


def candidate(kind: str, name: str, definition: str, source: str) -> dict | None:
    name = strip_markup(name)
    if not valid_name(name):
        return None
    return {
        "kind": kind,
        "name": name,
        "definition": strip_markup(definition),
        "source": source,
    }


def table_candidates(path: Path, repo_root: Path) -> list[dict]:
    if not path.is_file():
        return []
    source = repo_relative(repo_root, path)
    result: list[dict] = []
    for title, body in split_sections(path.read_text(encoding="utf-8")):
        heading = normalized_heading(title)
        term_section = "名词解释" in heading or "业务术语" in heading or heading == "术语表"
        role_section = "用户角色" in heading or "角色清单" in heading or heading == "用户画像"
        if not term_section and not role_section:
            continue
        for header, rows in tables(body):
            normalized = [re.sub(r"\s+", "", value) for value in header]
            if term_section:
                name_index = next((i for i, value in enumerate(normalized) if "术语" in value or value == "名词"), None)
                kind = "term"
            else:
                name_index = next(
                    (
                        i
                        for i, value in enumerate(normalized)
                        if value in {"角色", "角色名", "用户角色"}
                    ),
                    None,
                )
                kind = "role"
            if name_index is None:
                continue
            definition_index = next(
                (
                    i
                    for i, value in enumerate(normalized)
                    if any(marker in value for marker in ("说明", "定义", "描述", "含义"))
                ),
                None,
            )
            for row in rows:
                if name_index >= len(row):
                    continue
                definition = row[definition_index] if definition_index is not None and definition_index < len(row) else ""
                item = candidate(kind, row[name_index], definition, source)
                if item:
                    result.append(item)
    return result


def decision_candidates(path: Path, repo_root: Path) -> list[dict]:
    if not path.is_file():
        return []
    source = repo_relative(repo_root, path)
    result: list[dict] = []
    pattern = re.compile(
        r"^\s*(?:[-*]\s*)?(?:\*\*)?(业务术语|术语|用户角色|角色)(?:\*\*)?\s*[：:]\s*(.+?)\s*$"
    )
    for title, body in split_sections(path.read_text(encoding="utf-8")):
        if not re.match(r"^D\d+(?:[.、：:\s-]|$)", strip_markup(title), re.IGNORECASE):
            continue
        if decision_is_question(title, body):
            continue
        if decision_is_superseded(title, body):
            continue
        for line in body.splitlines():
            match = pattern.match(line)
            if not match:
                continue
            value = match.group(2).split("|", 1)[0].strip()
            kind = "role" if "角色" in match.group(1) else "term"
            item = candidate(kind, value, "", source)
            if item:
                result.append(item)
    return result


def accepted_delta_candidates(build: dict, source: str) -> list[dict]:
    result: list[dict] = []
    deltas = build.get("accepted_deltas", [])
    if not isinstance(deltas, list):
        return result
    for delta in deltas:
        if not isinstance(delta, dict):
            continue
        affects = delta.get("affects", [])
        if isinstance(affects, list):
            for affect in affects:
                if not isinstance(affect, dict):
                    continue
                kind = str(affect.get("kind") or "").strip().lower()
                name = affect.get("name")
                if kind not in {"term", "role"} or not isinstance(name, str):
                    continue
                item = candidate(kind, name.strip(), "", source)
                if item:
                    result.append(item)
        raw_kind = str(delta.get("kind", "")).strip().lower()
        if raw_kind in TERM_KINDS:
            kind = "term"
        elif raw_kind in ROLE_KINDS:
            kind = "role"
        else:
            continue
        summary = delta.get("summary")
        if not isinstance(summary, str):
            continue
        value = re.sub(r"^(?:业务术语|术语|用户角色|角色)\s*[：:]\s*", "", summary).strip()
        item = candidate(kind, value, "", source)
        if item:
            result.append(item)
    return result


def load_build(module_dir: Path) -> dict:
    path = module_dir / ".work-meta.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    build = data.get("build") if isinstance(data, dict) else None
    return build if isinstance(build, dict) else {}


def safe_spec_source(repo_root: Path, value: str) -> Path | None:
    path = Path(value).expanduser()
    path = path if path.is_absolute() else repo_root / path
    try:
        relative = path.resolve().relative_to(repo_root.resolve())
    except ValueError:
        return None
    parts = relative.parts
    if len(parts) < 3 or parts[:2] != ("docs", "modules") or path.suffix.lower() != ".md":
        return None
    # Durable product specs are either docs/modules/<name>.md functional specs
    # or a module's docs/modules/<module>/spec.md. Process notes and indexes
    # must never promote draft terminology into PRODUCT.md.
    if len(parts) == 3:
        return path.resolve() if path.name != "INDEX.md" else None
    return path.resolve() if path.name == "spec.md" else None


def collect_spec_sources(repo_root: Path, module_dir: Path, build: dict, extras: list[str]) -> list[Path]:
    result = [module_dir / "spec.md"]
    anchor = build.get("anchor")
    if isinstance(anchor, str):
        path = safe_spec_source(repo_root, anchor)
        if path:
            result.append(path)
    for value in extras:
        path = safe_spec_source(repo_root, value)
        if path:
            result.append(path)
    seen: set[Path] = set()
    unique: list[Path] = []
    for path in result:
        if path in seen:
            continue
        seen.add(path)
        unique.append(path)
    return unique


def load_registered(product_path: Path) -> dict[str, set[str]]:
    registered = {"terms": set(), "roles": set()}
    if not product_path.is_file():
        return registered
    for item in table_candidates(product_path, product_path.parent):
        key = "roles" if item["kind"] == "role" else "terms"
        registered[key].add(item["name"])
    return registered


def load_skip_list(work_dir: Path) -> set[str]:
    path = work_dir / ".term-skip.json"
    if not path.is_file():
        return set()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return set()
    if not isinstance(data, dict):
        return set()
    result: set[str] = set()
    for field in ("skipped_terms", "skipped_roles"):
        values = data.get(field, [])
        if isinstance(values, list):
            result.update(str(value).strip() for value in values if str(value).strip())
    return result


def reconcile(repo_root: Path, module_dir: Path, extras: list[str], work_dir: Path) -> dict:
    build = load_build(module_dir)
    candidates: list[dict] = []
    for path in collect_spec_sources(repo_root, module_dir, build, extras):
        candidates.extend(table_candidates(path, repo_root))
    candidates.extend(decision_candidates(module_dir / "decisions.md", repo_root))
    candidates.extend(accepted_delta_candidates(build, repo_relative(repo_root, module_dir / ".work-meta.json")))

    deduped: list[dict] = []
    indexes: dict[str, int] = {}
    for item in candidates:
        name = item["name"]
        if name in indexes:
            existing = deduped[indexes[name]]
            if item["kind"] == "role" and existing["kind"] != "role":
                existing["kind"] = "role"
            if not existing["definition"] and item["definition"]:
                existing["definition"] = item["definition"]
            continue
        indexes[name] = len(deduped)
        deduped.append(item)

    whitelist = load_whitelist()
    registered = load_registered(repo_root / "PRODUCT.md")
    skipped_names = load_skip_list(work_dir)
    new_terms: list[str] = []
    new_roles: list[str] = []
    whitelisted: list[str] = []
    registered_names: list[str] = []
    skipped: list[str] = []
    new_candidates: list[dict] = []
    for item in deduped:
        name = item["name"]
        if name in whitelist:
            whitelisted.append(name)
        elif name in registered["terms"] or name in registered["roles"]:
            registered_names.append(name)
        elif name in skipped_names:
            skipped.append(name)
        else:
            new_candidates.append(item)
            (new_roles if item["kind"] == "role" else new_terms).append(name)

    return {
        "new_terms": new_terms,
        "new_roles": new_roles,
        "skipped": skipped,
        "whitelisted": whitelisted,
        "registered": registered_names,
        "candidates": new_candidates,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module_dir", help="active docs/modules/<module> directory")
    parser.add_argument("repo_root", help="consumer repository root")
    parser.add_argument("--source", action="append", default=[], help="additional landed markdown source")
    parser.add_argument("--work-dir", help="directory containing optional .term-skip.json")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).expanduser().resolve()
    module_dir = Path(args.module_dir).expanduser().resolve()
    try:
        module_dir.relative_to(repo_root)
    except ValueError:
        print(json.dumps({"error": f"module is outside repository: {module_dir}"}, ensure_ascii=False), file=sys.stderr)
        return 2
    if not module_dir.is_dir():
        print(json.dumps({"error": f"module directory not found: {module_dir}"}, ensure_ascii=False), file=sys.stderr)
        return 2
    work_dir = Path(args.work_dir).expanduser().resolve() if args.work_dir else module_dir
    result = reconcile(repo_root, module_dir, args.source, work_dir)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
