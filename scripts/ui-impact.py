#!/usr/bin/env python3
"""Check high-risk UI edits before they reach a shared primitive.

The check is intentionally small: it follows local imports, reports layout
constraints found in the referenced primitive, and verifies measured browser
dimensions when called with ``verify-size``. It does not attempt to replace a
visual review or a project's design-system tooling.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


UI_EXTENSIONS = {".css", ".jsx", ".js", ".scss", ".tsx", ".ts", ".vue"}
RISK_PATTERN = re.compile(
    r"(?:\bDialog\b|\bDrawer\b|\bSheet\b|\bPopover\b|className\s*=|"
    r"(?:max|min)-[wh]-|\b[wh]-\[[^\]]+\]|\b(?:grid|flex|columns|gap)-)"
)
IMPORT_PATTERN = re.compile(
    r"import\s+(?P<clause>[\s\S]*?)\s+from\s+[\"'](?P<source>[^\"']+)[\"']"
)
CONSTRAINT_PATTERN = re.compile(
    r"(?<![A-Za-z0-9_-])(?:[a-z0-9-]+:)*(?:!?)(?:(?:max|min)-[wh]|[wh])-[^\s\"'`}>]+"
)
WIDTH_PATTERN = re.compile(
    r"(?:max-w|w-|width\s*:|grid-cols|flex(?:-basis)?|columns-|\bDialog\b|\bDrawer\b|\bSheet\b)"
)


def _relative(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def _candidate_paths(root: Path, source_file: Path, specifier: str) -> list[Path]:
    if specifier.startswith("."):
        base = source_file.parent / specifier
    elif specifier.startswith("@/"):
        relative = specifier[2:]
        base = root / "src" / relative
        if not base.exists() and not any(
            base.with_suffix(extension).is_file()
            for extension in (".tsx", ".ts", ".jsx", ".js", ".vue")
        ):
            base = root / relative
    else:
        return []

    candidates = [base]
    if not base.suffix:
        candidates.extend(base.with_suffix(extension) for extension in (".tsx", ".ts", ".jsx", ".js", ".vue"))
        candidates.extend(base / f"index{extension}" for extension in (".tsx", ".ts", ".jsx", ".js", ".vue"))
    return [candidate for candidate in candidates if candidate.is_file()]


def _import_symbols(clause: str) -> list[str]:
    names: list[str] = []
    named = re.search(r"\{(?P<body>[\s\S]*?)\}", clause)
    if named:
        for item in named.group("body").split(","):
            value = item.strip().split(" as ", 1)[0].strip()
            if value:
                names.append(value)
    default = re.match(r"\s*([A-Za-z_$][\w$]*)", clause)
    if default:
        names.append(default.group(1))
    return list(dict.fromkeys(names))


def _primitive_refs(root: Path, source_file: Path, source: str) -> list[dict[str, Any]]:
    refs: list[dict[str, Any]] = []
    for match in IMPORT_PATTERN.finditer(source):
        specifier = match.group("source")
        paths = _candidate_paths(root, source_file, specifier)
        if not paths:
            continue
        primitive = paths[0]
        primitive_source = _read(primitive)
        constraints = sorted(set(CONSTRAINT_PATTERN.findall(primitive_source)))
        if not constraints and "/components/" not in primitive.as_posix():
            continue
        refs.append(
            {
                "symbols": _import_symbols(match.group("clause")),
                "specifier": specifier,
                "path": _relative(primitive, root),
                "constraints": constraints,
            }
        )
    return refs


def inspect(args: argparse.Namespace) -> int:
    root = Path(args.repo_root).expanduser().resolve()
    path = Path(args.path).expanduser()
    if not path.is_absolute():
        path = root / path
    path = path.resolve()
    source = _read(path)
    proposed = args.proposed_text or ""
    combined = f"{source}\n{proposed}"
    high_risk = path.suffix.lower() in UI_EXTENSIONS and bool(RISK_PATTERN.search(combined))
    refs = _primitive_refs(root, path, source) if source else []
    constrained_refs = [ref for ref in refs if ref["constraints"]]
    width_change = bool(WIDTH_PATTERN.search(proposed or source))
    has_explicit_override = bool(
        re.search(r"(?:!max-w|!min-w|!w-|!max-h|!min-h|!h-|!important|style\s*=)", proposed)
    )
    findings: list[dict[str, str]] = []
    if high_risk and width_change and constrained_refs and not has_explicit_override:
        findings.append(
            {
                "code": "primitive-override-risk",
                "severity": "block",
                "message": "共享 primitive 含尺寸约束，当前改动没有明确覆盖规则；先核对 cascade/variant，再修改页面。",
            }
        )
    if high_risk and width_change and not refs:
        findings.append(
            {
                "code": "primitive-unresolved",
                "severity": "check",
                "message": "未解析到本地共享 primitive；请人工确认外部组件 / alias 的真实尺寸约束，并将结果记为 limited。",
            }
        )
    if high_risk and width_change:
        findings.append(
            {
                "code": "actual-size-required",
                "severity": "check",
                "message": "修改后必须在 browser manifest 中加入 size 实际尺寸断言。",
            }
        )

    if any(item["severity"] == "block" for item in findings):
        status = "needs-review"
    elif any(item["code"] == "primitive-unresolved" for item in findings):
        status = "limited"
    else:
        status = "pass"
    report = {
        "schema_version": 1,
        "check": "ui-impact",
        "status": status,
        "path": _relative(path, root),
        "high_risk": high_risk,
        "width_or_layout_change": width_change,
        "primitive_refs": refs,
        "findings": findings,
        "requires_actual_size": high_risk and width_change,
    }
    if args.output:
        output = Path(args.output).expanduser()
        if not output.is_absolute():
            output = root / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if status == "needs-review" else 0


def verify_size(args: argparse.Namespace) -> int:
    try:
        expected = float(args.expected)
        actual = float(args.actual)
        tolerance = float(args.tolerance)
    except ValueError as exc:
        raise SystemExit("expected / actual / tolerance 必须是数字。") from exc
    if tolerance < 0:
        raise SystemExit("tolerance 不能为负数。")
    delta = abs(actual - expected)
    report = {
        "schema_version": 1,
        "check": "ui-size",
        "status": "pass" if delta <= tolerance else "fail",
        "selector": args.selector,
        "dimension": args.dimension,
        "expected": expected,
        "actual": actual,
        "tolerance": tolerance,
        "delta": delta,
    }
    if args.output:
        output = Path(args.output).expanduser()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["status"] == "pass" else 1


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    sub = result.add_subparsers(dest="command", required=True)
    inspect_parser = sub.add_parser("inspect")
    inspect_parser.add_argument("--repo-root", default=".")
    inspect_parser.add_argument("--path", required=True)
    inspect_parser.add_argument("--proposed-text", default="")
    inspect_parser.add_argument("--output")
    inspect_parser.set_defaults(func=inspect)
    size_parser = sub.add_parser("verify-size")
    size_parser.add_argument("--selector", required=True)
    size_parser.add_argument("--dimension", choices=("width", "height"), default="width")
    size_parser.add_argument("--expected", required=True)
    size_parser.add_argument("--actual", required=True)
    size_parser.add_argument("--tolerance", default="2")
    size_parser.add_argument("--output")
    size_parser.set_defaults(func=verify_size)
    return result


if __name__ == "__main__":
    parsed = parser().parse_args()
    raise SystemExit(parsed.func(parsed))
