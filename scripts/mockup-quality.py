#!/usr/bin/env python3
"""Compile and verify the design-quality evidence for a mockup round."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any


SCHEMA_VERSION = 1
REPORT_SCHEMA_VERSION = 1
REQUIRED_CHECKS = {
    "design-principles",
    "existing-shell-and-components",
    "information-hierarchy",
    "task-path-and-states",
    "responsive-layout",
    "text-and-controls",
}


class QualityError(RuntimeError):
    pass


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="minutes")


def _valid_timestamp(value: Any) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    try:
        datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def _slug(value: str, fallback: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9]+", "-", value).strip("-").lower()
    if normalized:
        return normalized[:80]
    digest = hashlib.sha1(value.encode("utf-8")).hexdigest()[:10]
    return f"{fallback}-{digest}"


def _repo_path(
    repo: Path,
    raw: str,
    label: str,
    *,
    must_exist: bool = True,
    inside_mockups: bool = False,
) -> tuple[Path, str]:
    relative = PurePosixPath(raw)
    if not raw.strip() or relative.is_absolute() or ".." in relative.parts:
        raise QualityError(f"{label} 必须是仓内相对路径: {raw}")
    normalized = relative.as_posix()
    if inside_mockups and not normalized.startswith("mockups/"):
        raise QualityError(f"{label} 必须位于 mockups/ 内: {raw}")
    candidate = repo.joinpath(*relative.parts)
    resolved_repo = repo.resolve()
    try:
        resolved = candidate.resolve(strict=must_exist)
        resolved.relative_to(resolved_repo)
    except (OSError, RuntimeError, ValueError) as exc:
        raise QualityError(f"{label} 不存在或越出仓库: {raw}") from exc
    if must_exist and (candidate.is_symlink() or not resolved.is_file()):
        raise QualityError(f"{label} 必须是仓内普通文件: {raw}")
    return resolved, normalized


def _read_json(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise QualityError(f"{label} 不是合法 JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise QualityError(f"{label} 顶层必须是对象")
    return value


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")
        temporary = Path(handle.name)
    temporary.replace(path)


def _nonempty_strings(values: list[str], label: str) -> list[str]:
    result = [value.strip() for value in values if value.strip()]
    if not result:
        raise QualityError(f"至少提供一条{label}")
    return result


def _items(prefix: str, values: list[str]) -> list[dict[str, str]]:
    return [
        {"id": f"{prefix}-{index}", "text": value}
        for index, value in enumerate(values, start=1)
    ]


def _design_system_source(repo: Path, design_text: str) -> dict[str, Any]:
    section_match = re.search(
        r"^##\s+.*项目设计系统.*$([\s\S]*?)(?=^##\s+|\Z)",
        design_text,
        flags=re.MULTILINE,
    )
    section = section_match.group(1) if section_match else ""

    def field(name: str) -> str:
        match = re.search(rf"^-\s*{re.escape(name)}：\s*(.*?)\s*$", section, re.MULTILINE)
        if not match:
            return ""
        return re.sub(r"<!--.*?-->", "", match.group(1)).strip()

    status = field("状态") or "未声明"
    source: dict[str, Any] = {
        "status": status,
        "name": field("设计系统"),
        "scope": field("使用范围"),
        "skill": field("项目级 Skill"),
        "skill_file": field("Skill 文件"),
    }
    if status != "已接入":
        return source
    missing = [key for key in ("name", "scope", "skill", "skill_file") if not source[key]]
    if missing:
        raise QualityError("DESIGN.md 已声明接入设计系统，但缺少：" + ", ".join(missing))
    skill_path, normalized = _repo_path(repo, source["skill_file"], "项目设计系统 Skill")
    tracked = subprocess.run(
        ["git", "-C", str(repo), "ls-files", "--error-unmatch", normalized],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if tracked.returncode != 0:
        raise QualityError(f"项目设计系统 Skill 尚未被 Git 跟踪: {normalized}")
    source["skill_file"] = normalized
    source["skill_sha256"] = _sha256(skill_path)
    return source


def compile_contract(args: argparse.Namespace) -> int:
    repo = Path(args.repo).expanduser().resolve()
    if not repo.is_dir():
        raise QualityError(f"消费仓不存在: {repo}")
    design_path, design_relative = _repo_path(repo, "DESIGN.md", "DESIGN.md")
    design_text = design_path.read_text(encoding="utf-8")

    references: list[dict[str, str]] = []
    for raw in args.reference:
        path, normalized = _repo_path(repo, raw, "现有界面参考")
        references.append({"path": normalized, "sha256": _sha256(path)})
    if not references and not args.new_visual_baseline:
        raise QualityError("已有产品必须至少绑定一个现有页面、组件或样式；全新产品请显式传 --new-visual-baseline")

    constraints = {
        "must_inherit": _items(
            "must-inherit", _nonempty_strings(args.must_inherit, "必须继承的设计约束")
        ),
        "reuse": _items("reuse", _nonempty_strings(args.reuse, "必须复用的界面或组件模式")),
        "may_change": _items(
            "may-change", _nonempty_strings(args.may_change, "本轮允许改变的内容")
        ),
        "guardrails": _items(
            "guardrail", _nonempty_strings(args.guardrail, "本轮设计护栏")
        ),
    }
    requirement = args.requirement.strip()
    round_label = args.round.strip()
    round_goal = args.round_goal.strip()
    if not requirement or not round_label or not round_goal:
        raise QualityError("需求、轮次和本轮要判断的问题都不能为空")

    default_out = (
        f"mockups/audits/{_slug(requirement, 'requirement')}/"
        f"{_slug(round_label, 'round')}/design-basis.json"
    )
    out_path, out_relative = _repo_path(
        repo,
        args.out or default_out,
        "设计依据输出",
        must_exist=False,
        inside_mockups=True,
    )
    payload = {
        "schema_version": SCHEMA_VERSION,
        "kind": "mockup-design-basis",
        "requirement": requirement,
        "round": round_label,
        "round_goal": round_goal,
        "compiled_at": _now(),
        "sources": {
            "design": {"path": design_relative, "sha256": _sha256(design_path)},
            "project_design_system": _design_system_source(repo, design_text),
            "existing_ui": references,
            "new_visual_baseline": bool(args.new_visual_baseline),
        },
        "constraints": constraints,
    }
    _write_json(out_path, payload)
    print(f"DESIGN_BASIS: {out_relative}")
    return 0


def _verify_source(repo: Path, source: dict[str, Any], label: str) -> None:
    if not isinstance(source, dict):
        raise QualityError(f"设计依据缺少 {label}")
    path, _ = _repo_path(repo, str(source.get("path") or ""), label)
    expected = str(source.get("sha256") or "")
    if not expected or _sha256(path) != expected:
        raise QualityError(f"{label} 已变化，请重新编译本轮设计依据")


def init_audit(args: argparse.Namespace) -> int:
    repo = Path(args.repo).expanduser().resolve()
    contract_path, contract_relative = _repo_path(
        repo, args.contract, "设计依据", inside_mockups=True
    )
    contract = _read_json(contract_path, "设计依据")
    if contract.get("schema_version") != SCHEMA_VERSION or contract.get("kind") != "mockup-design-basis":
        raise QualityError("设计依据格式不受支持")
    variants = _nonempty_strings(args.variant, "候选方向路径")
    normalized_variants = [
        _repo_path(
            repo,
            raw,
            "候选方向路径",
            must_exist=False,
            inside_mockups=True,
        )[1]
        for raw in variants
    ]
    if len(set(normalized_variants)) != len(normalized_variants):
        raise QualityError("候选方向路径不能重复")

    constraints = contract.get("constraints")
    if not isinstance(constraints, dict):
        raise QualityError("设计依据缺少约束清单")
    constraint_items = [
        item
        for group in constraints.values()
        if isinstance(group, list)
        for item in group
        if isinstance(item, dict) and item.get("id") and item.get("text")
    ]
    if not constraint_items:
        raise QualityError("设计依据约束清单为空")

    out_default = PurePosixPath(contract_relative).parent / "visual-audit.json"
    out_path, out_relative = _repo_path(
        repo,
        args.out or out_default.as_posix(),
        "视觉验收报告输出",
        must_exist=False,
        inside_mockups=True,
    )
    checks = [
        {"id": check_id, "status": "pending", "evidence": ""}
        for check_id in sorted(REQUIRED_CHECKS)
    ]
    constraint_results = [
        {
            "id": str(item["id"]),
            "status": "pending",
            "evidence": "",
        }
        for item in constraint_items
    ]
    payload = {
        "schema_version": REPORT_SCHEMA_VERSION,
        "kind": "mockup-visual-audit",
        "design_basis": contract_relative,
        "design_basis_sha256": _sha256(contract_path),
        "audited_at": "",
        "browser_adapter": "",
        "variants": [
            {
                "path": variant,
                "screenshots": {
                    "desktop": {"path": "", "width": 0, "height": 0, "sha256": "", "captured_at": ""},
                    "narrow": {"path": "", "width": 0, "height": 0, "sha256": "", "captured_at": ""},
                },
                "checks": [dict(item) for item in checks],
                "constraint_results": [dict(item) for item in constraint_results],
                "observations": [],
            }
            for variant in normalized_variants
        ],
    }
    _write_json(out_path, payload)
    print(f"VISUAL_AUDIT_TEMPLATE: {out_relative}")
    return 0


def _png_dimensions(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise QualityError(f"视觉证据必须是真实 PNG 截图: {path.name}")
    return struct.unpack(">II", header[16:24])


def _verify_pass_entries(
    entries: Any,
    label: str,
    required_ids: set[str],
) -> None:
    if not isinstance(entries, list):
        raise QualityError(f"{label} 必须是数组")
    by_id: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            raise QualityError(f"{label} 每项必须是对象")
        entry_id = str(entry.get("id") or "").strip()
        if not entry_id or entry_id in by_id:
            raise QualityError(f"{label} 存在空或重复 id")
        by_id[entry_id] = entry
    missing = sorted(required_ids - set(by_id))
    if missing:
        raise QualityError(f"{label} 缺少：{', '.join(missing)}")
    for entry_id in sorted(required_ids):
        entry = by_id[entry_id]
        if entry.get("status") != "pass":
            raise QualityError(f"{label} 未通过：{entry_id}")
        if not isinstance(entry.get("evidence"), str) or not entry["evidence"].strip():
            raise QualityError(f"{label} 缺少具体证据：{entry_id}")


def _verify_screenshot(
    repo: Path,
    raw: Any,
    label: str,
    *,
    desktop: bool,
) -> None:
    if not isinstance(raw, dict):
        raise QualityError(f"缺少{label}截图")
    path, _ = _repo_path(
        repo,
        str(raw.get("path") or ""),
        f"{label}截图",
        inside_mockups=True,
    )
    width, height = _png_dimensions(path)
    if raw.get("width") != width or raw.get("height") != height:
        raise QualityError(f"{label}截图记录尺寸与实际 PNG 不一致")
    if raw.get("sha256") != _sha256(path):
        raise QualityError(f"{label}截图内容摘要不一致")
    if not _valid_timestamp(raw.get("captured_at")):
        raise QualityError(f"{label}截图缺少合法 captured_at")
    if desktop and (width < 1024 or height < 640):
        raise QualityError("桌面截图至少需要 1024x640")
    if not desktop and (width < 320 or width > 480 or height < 640):
        raise QualityError("窄屏截图宽度需为 320-480，高度至少 640")


def verify_report(args: argparse.Namespace) -> int:
    repo = Path(args.repo).expanduser().resolve()
    contract_path, contract_relative = _repo_path(
        repo, args.contract, "设计依据", inside_mockups=True
    )
    report_path, _ = _repo_path(repo, args.report, "视觉验收报告", inside_mockups=True)
    contract = _read_json(contract_path, "设计依据")
    report = _read_json(report_path, "视觉验收报告")
    if contract.get("schema_version") != SCHEMA_VERSION or contract.get("kind") != "mockup-design-basis":
        raise QualityError("设计依据格式不受支持")
    if report.get("schema_version") != REPORT_SCHEMA_VERSION or report.get("kind") != "mockup-visual-audit":
        raise QualityError("视觉验收报告格式不受支持")
    if not _valid_timestamp(report.get("audited_at")):
        raise QualityError("视觉验收报告缺少合法 audited_at")
    if not isinstance(report.get("browser_adapter"), str) or not report["browser_adapter"].strip():
        raise QualityError("视觉验收报告必须记录 browser_adapter")
    if report.get("design_basis") != contract_relative:
        raise QualityError("视觉验收报告没有绑定当前设计依据路径")
    if report.get("design_basis_sha256") != _sha256(contract_path):
        raise QualityError("视觉验收报告没有绑定当前设计依据内容")

    sources = contract.get("sources")
    if not isinstance(sources, dict):
        raise QualityError("设计依据缺少来源")
    _verify_source(repo, sources.get("design"), "DESIGN.md")
    existing_ui = sources.get("existing_ui")
    if not isinstance(existing_ui, list):
        raise QualityError("设计依据缺少现有界面参考")
    for index, source in enumerate(existing_ui, start=1):
        _verify_source(repo, source, f"现有界面参考 {index}")
    design_system = sources.get("project_design_system")
    if isinstance(design_system, dict) and design_system.get("status") == "已接入":
        _verify_source(
            repo,
            {
                "path": design_system.get("skill_file"),
                "sha256": design_system.get("skill_sha256"),
            },
            "项目设计系统 Skill",
        )

    constraints = contract.get("constraints")
    if not isinstance(constraints, dict):
        raise QualityError("设计依据缺少约束清单")
    constraint_ids = {
        str(item.get("id"))
        for group in constraints.values()
        if isinstance(group, list)
        for item in group
        if isinstance(item, dict) and item.get("id")
    }
    if not constraint_ids:
        raise QualityError("设计依据约束清单为空")

    variants = report.get("variants")
    if not isinstance(variants, list) or not variants:
        raise QualityError("视觉验收报告至少包含一个方向")
    seen: set[str] = set()
    for index, variant in enumerate(variants, start=1):
        if not isinstance(variant, dict):
            raise QualityError(f"视觉验收方向 {index} 必须是对象")
        _, variant_path = _repo_path(
            repo,
            str(variant.get("path") or ""),
            f"方向 {index}",
            inside_mockups=True,
        )
        if variant_path in seen:
            raise QualityError(f"视觉验收方向重复: {variant_path}")
        seen.add(variant_path)
        screenshots = variant.get("screenshots")
        if not isinstance(screenshots, dict):
            raise QualityError(f"方向 {index} 缺少截图")
        _verify_screenshot(repo, screenshots.get("desktop"), "桌面", desktop=True)
        _verify_screenshot(repo, screenshots.get("narrow"), "窄屏", desktop=False)
        _verify_pass_entries(variant.get("checks"), "视觉检查", REQUIRED_CHECKS)
        _verify_pass_entries(
            variant.get("constraint_results"), "设计约束检查", constraint_ids
        )
        observations = variant.get("observations")
        if not isinstance(observations, list) or not observations or any(
            not isinstance(item, str) or not item.strip() for item in observations
        ):
            raise QualityError(f"方向 {index} 必须记录视觉走查观察")

    required_variants = {
        _repo_path(repo, raw, "待核对候选方向", inside_mockups=True)[1]
        for raw in args.variant
    }
    missing_variants = sorted(required_variants - seen)
    if missing_variants:
        raise QualityError("视觉验收报告未覆盖候选方向：" + ", ".join(missing_variants))

    print(f"MOCKUP_QUALITY: PASS ({len(variants)} 个方向)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="编译并验证 mockup 设计质量合同")
    subparsers = parser.add_subparsers(dest="command", required=True)

    compile_parser = subparsers.add_parser("compile", help="编译本轮设计依据")
    compile_parser.add_argument("--repo", required=True, help="消费仓根目录")
    compile_parser.add_argument("--requirement", required=True, help="需求 / 模块名")
    compile_parser.add_argument("--round", required=True, help="探索轮次")
    compile_parser.add_argument("--round-goal", required=True, help="本轮要判断的产品问题")
    compile_parser.add_argument("--reference", action="append", default=[], help="现有页面、组件或样式的仓内相对路径，可重复")
    compile_parser.add_argument("--new-visual-baseline", action="store_true", help="全新产品没有可复用现有界面")
    compile_parser.add_argument("--must-inherit", action="append", default=[], help="必须继承的设计要求，可重复")
    compile_parser.add_argument("--reuse", action="append", default=[], help="必须复用的界面或组件模式，可重复")
    compile_parser.add_argument("--may-change", action="append", default=[], help="本轮允许改变的内容，可重复")
    compile_parser.add_argument("--guardrail", action="append", default=[], help="本轮设计护栏，可重复")
    compile_parser.add_argument("--out", help="输出仓内路径，默认位于 mockups/audits/")
    compile_parser.set_defaults(handler=compile_contract)

    verify_parser = subparsers.add_parser("verify", help="验证桌面与窄屏视觉验收报告")
    verify_parser.add_argument("--repo", required=True, help="消费仓根目录")
    verify_parser.add_argument("--contract", required=True, help="设计依据的仓内相对路径")
    verify_parser.add_argument("--report", required=True, help="视觉验收报告的仓内相对路径")
    verify_parser.add_argument("--variant", action="append", default=[], help="必须由报告覆盖的候选方向仓内路径，可重复")
    verify_parser.set_defaults(handler=verify_report)

    init_parser = subparsers.add_parser("init-audit", help="按设计依据生成视觉验收报告骨架")
    init_parser.add_argument("--repo", required=True, help="消费仓根目录")
    init_parser.add_argument("--contract", required=True, help="设计依据的仓内相对路径")
    init_parser.add_argument("--variant", action="append", default=[], help="候选方向的仓内路径，可重复；可在资产复制前声明")
    init_parser.add_argument("--out", help="报告输出仓内路径，默认与设计依据同目录")
    init_parser.set_defaults(handler=init_audit)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return int(args.handler(args))
    except (QualityError, UnicodeError) as exc:
        print(f"MOCKUP_QUALITY: FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
