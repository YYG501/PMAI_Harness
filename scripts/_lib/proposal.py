"""Validate the current Product Proposal and its compact machine contract."""

from __future__ import annotations

import hashlib
import json
import os
import re
import stat
import subprocess
from datetime import date, datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any

from _lib.atomic_file import AtomicFileError, ensure_directory_beneath, write_text_atomically


SCHEMA_VERSION = 3
ATOMIC_SCHEMA_VERSION = 2
SUPPORTED_SCHEMA_VERSIONS = (1, 2, SCHEMA_VERSION)
CONTRACT_RELATIVE_PATH = PurePosixPath(".pm-workflow/proposal.json")
INTAKE_MANIFEST_RELATIVE_PATH = PurePosixPath(".pm-workflow/intake-manifest.json")
INTAKE_MANIFEST_SCHEMA_VERSION = 1
INTAKE_MANIFEST_MAX_FILE_BYTES = 64 * 1024 * 1024
INTAKE_MANIFEST_MAX_FILES = 100_000
INTAKE_CAPTURE_BLOCKING_PATHS = (
    ".pm-workflow/intake-manifest.json",
    ".opencode/commands/pmai-build.md",
)
INTAKE_CAPTURE_MARKER_FILES = (
    "AGENTS.md",
    "CLAUDE.md",
    "PRODUCT.md",
    "PRODUCT-STATE.md",
    "docs/CODEBASE-AUDIT.md",
    "docs/CONTEXT.md",
    ".pm-workflow/config.yml",
    ".pm-workflow/project.yml",
    ".pm-workflow/proposal.json",
    ".claude/settings.json",
    ".codex/hooks.json",
    "opencode.json",
)
PROPOSAL_REQUIRED_MARKER = "<!-- PMAI_PROPOSAL_REQUIRED -->"
VALID_STATUS = "accepted"
ACTIVE_BUILD_LIFECYCLES = {"building", "iterating", "final_check"}
BASE_CONTRACT_FIELDS = {
    "schema_version",
    "id",
    "status",
    "path",
    "hash",
    "accepted_at",
    "supersedes",
}
PRODUCT_HASH_FIELD = "product_hash"
HANDOFF_FIELDS = {
    "第一个 design 目标": "first_design_goal",
    "主用户与触发时刻": "primary_user_and_trigger",
    "要闭合的核心任务": "core_task",
    "必须保持的产品回答": "product_answer",
    "必须保持的产品边界": "product_boundary",
    "MVP 必须证明": "mvp_evidence",
    "仍待验证的假设": "open_hypotheses",
    "design 需要收敛": "design_unknowns",
}
PROPOSAL_HEADER_FIELDS = (
    "版本",
    "Proposal ID",
    "状态",
    "日期",
    "取代",
    "支持的决定",
    "证据截至",
)
PROPOSAL_SECTION_PATTERNS = {
    0: r"决策摘要与产品主张",
    1: r"产品成立的核心判断",
    2: r"用户、场景、问题与现状替代",
    3: r"产品回答与职责边界",
    4: r"必要能力与\s*AI\s*角色",
    5: r"替代方案、竞争判断与产品机会",
    6: r"端到端产品体验与关键能力",
    7: r"产品价值、因果链与指标",
    8: r"MVP\s*范围、(?:完整案例|完整\s*Case(?:\s*Rundown)?)与决策门",
    9: r"演进条件与长期方向",
    10: r"下游交接摘要",
}
PRODUCT_BASELINE_SECTIONS = (
    "当前 Product Proposal",
    "产品定位",
    "核心问题与价值",
    "用户画像",
    "产品边界",
    "MVP Case",
)
EQUIVALENT_BASELINE_CHECKS = (
    ("产品定位", (r"产品定位", r"一句话定位")),
    (
        "主用户",
        (
            r"用户画像",
            r"目标用户(?:和强场景)?",
            r"用户[、与和]场景",
            r"角色[、与和]场景",
        ),
    ),
    ("核心问题与价值", (r"核心问题与价值", r"核心问题", r"要解决的真实问题", r"问题与价值")),
    ("产品边界", (r"产品边界", r"职责边界", r"范围与边界", r"非目标")),
)
CURRENT_RESULT_SECTION_PATTERNS = (
    r"当前功能(?:\s*/\s*能力)?",
    r"当前界面(?:\s*/\s*产品形态)?",
    r"当前产品结果",
    r"当前能力",
    r"已落地结果",
)
EQUIVALENT_BASELINE_SECTION_PATTERN = r"当前 Product Proposal"
EQUIVALENT_BASELINE_DECLARATION = "接入前已有等价产品基线"
EQUIVALENT_BASELINE_DECLARATION_GAPS = (
    "等价基线声明",
    "等价基线主要依据",
    "等价基线 PM 确认日期",
)
EQUIVALENT_BASELINE_GIT_GAP = "等价基线 Git 完整性"
EQUIVALENT_BASELINE_MANIFEST_GAP = "接入前依据 manifest"
EQUIVALENT_BASELINE_FILE_GAP = "等价基线文件完整性"
PLACEHOLDER_ONLY_PATTERN = re.compile(
    r"(?:TODO|TBD|FIXME|N/?A|"
    r"待(?:完成|补充|确认|明确|填写|提供|更新|定稿|讨论|定)|"
    r"待验证|暂无(?:内容|数据|信息)?|未知|未定|未填写|未提供|"
    r"占位(?:内容|符)?|placeholder)",
    re.IGNORECASE,
)


class ProposalContractError(ValueError):
    """Raised when the Product Proposal contract is absent, unsafe, or stale."""


def _repo_root(value: Path | str) -> Path:
    root = Path(value).expanduser().resolve()
    if not root.is_dir():
        raise ProposalContractError(f"仓库不存在：{root}")
    return root


def contract_path(repo_root: Path | str) -> Path:
    return _repo_root(repo_root) / Path(CONTRACT_RELATIVE_PATH)


def intake_manifest_path(repo_root: Path | str) -> Path:
    return _repo_root(repo_root) / Path(INTAKE_MANIFEST_RELATIVE_PATH)


def _repo_relative_path(value: Any, *, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ProposalContractError(f"{label}必须是非空仓内相对路径。")
    if "\\" in value or "\x00" in value:
        raise ProposalContractError(f"{label}必须使用仓内相对 POSIX 路径。")
    path = PurePosixPath(value)
    if (
        path.is_absolute()
        or ".." in path.parts
        or path.as_posix() != value
        or value in {".", ""}
    ):
        raise ProposalContractError(
            f"{label}禁止绝对路径、路径穿越或非规范写法：{value}"
        )
    return value


def _resolve_repo_regular_file(
    repo_root: Path,
    relative: str,
    *,
    label: str,
) -> Path:
    normalized = _repo_relative_path(relative, label=f"{label}路径")
    lexical = repo_root / Path(normalized)
    try:
        resolved = lexical.resolve(strict=True)
        resolved.relative_to(repo_root)
        mode = resolved.stat().st_mode
    except (OSError, ValueError) as exc:
        raise ProposalContractError(f"{label}必须是仓库内普通文件：{relative}") from exc
    if resolved != lexical or not stat.S_ISREG(mode):
        raise ProposalContractError(
            f"{label}禁止 symlink、路径逃逸或非普通文件：{relative}"
        )
    return resolved


def _proposal_id(value: Any, label: str = "id") -> str:
    if not isinstance(value, str) or not re.fullmatch(
        r"[a-z0-9][a-z0-9._-]{1,127}", value
    ):
        raise ProposalContractError(
            f"{label} 必须是 2-128 位小写字母、数字、点、下划线或连字符。"
        )
    return value


def _proposal_relative_path(value: Any) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise ProposalContractError("path 必须是非空仓内相对路径。")
    if "\\" in value or "\x00" in value:
        raise ProposalContractError("path 必须使用仓内相对 POSIX 路径。")
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or path.as_posix() != value:
        raise ProposalContractError(f"path 禁止绝对路径、路径穿越或非规范写法：{value}")
    if path.parts[:2] != ("docs", "proposals") or len(path.parts) < 3:
        raise ProposalContractError("path 必须位于 docs/proposals/。")
    if path.suffix.lower() != ".md" or path.name.lower() == "index.md":
        raise ProposalContractError("path 必须指向 docs/proposals/ 下的版本化 Markdown 正文。")
    return value


def _sha256(value: Any) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ProposalContractError("hash 必须是 64 位小写 SHA-256。")
    return value


def _accepted_at(value: Any) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ProposalContractError("accepted_at 必须是带时区的 ISO-8601 时间。")
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ProposalContractError("accepted_at 必须是带时区的 ISO-8601 时间。") from exc
    if parsed.tzinfo is None:
        raise ProposalContractError("accepted_at 必须包含时区。")
    return value


def validate_contract_data(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProposalContractError("proposal.json 顶层必须是对象。")
    schema_version = value.get("schema_version")
    if schema_version not in SUPPORTED_SCHEMA_VERSIONS:
        versions = "、".join(str(item) for item in SUPPORTED_SCHEMA_VERSIONS)
        raise ProposalContractError(f"schema_version 必须是 {versions}。")
    expected_fields = set(BASE_CONTRACT_FIELDS)
    if schema_version == SCHEMA_VERSION:
        expected_fields.add(PRODUCT_HASH_FIELD)
    unknown = sorted(set(value) - expected_fields)
    missing = sorted(expected_fields - set(value))
    if unknown:
        raise ProposalContractError("proposal.json 含未知字段：" + "、".join(unknown))
    if missing:
        raise ProposalContractError("proposal.json 缺少字段：" + "、".join(missing))
    proposal_id = _proposal_id(value.get("id"))
    if value.get("status") != VALID_STATUS:
        raise ProposalContractError(f"status 必须是 {VALID_STATUS}。")
    proposal_path = _proposal_relative_path(value.get("path"))
    content_hash = _sha256(value.get("hash"))
    accepted_at = _accepted_at(value.get("accepted_at"))
    supersedes_value = value.get("supersedes")
    supersedes = None
    if supersedes_value is not None:
        supersedes = _proposal_id(supersedes_value, "supersedes")
        if supersedes == proposal_id:
            raise ProposalContractError("supersedes 不能与当前 id 相同。")
    normalized = {
        "schema_version": schema_version,
        "id": proposal_id,
        "status": VALID_STATUS,
        "path": proposal_path,
        "hash": content_hash,
        "accepted_at": accepted_at,
        "supersedes": supersedes,
    }
    if schema_version == SCHEMA_VERSION:
        normalized[PRODUCT_HASH_FIELD] = _sha256(value.get(PRODUCT_HASH_FIELD))
    return normalized


def load_contract_metadata(repo_root: Path | str) -> dict[str, Any]:
    path = contract_path(repo_root)
    if not path.exists():
        raise ProposalContractError(
            "缺少当前 Product Proposal 合同；全新项目请先完成 /pmai-proposal。"
        )
    if path.is_symlink() or not stat.S_ISREG(path.stat().st_mode):
        raise ProposalContractError(f"proposal.json 必须是仓库内普通文件：{path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ProposalContractError(f"无法读取 proposal.json：{exc}") from exc
    except json.JSONDecodeError as exc:
        raise ProposalContractError(f"proposal.json 不是合法 JSON：{exc}") from exc
    return validate_contract_data(value)


def resolve_proposal_path(repo_root: Path | str, value: str) -> Path:
    root = _repo_root(repo_root)
    relative = _proposal_relative_path(value)
    lexical = root / Path(relative)
    try:
        resolved = lexical.resolve(strict=True)
    except OSError as exc:
        raise ProposalContractError(f"当前 Product Proposal 不存在：{relative}") from exc
    proposals_root = (root / "docs" / "proposals").resolve()
    try:
        resolved.relative_to(proposals_root)
    except ValueError as exc:
        raise ProposalContractError(f"Product Proposal 解析后逃逸 docs/proposals/：{relative}") from exc
    if resolved != lexical:
        raise ProposalContractError(f"Product Proposal 路径含 symlink，拒绝使用：{relative}")
    if not stat.S_ISREG(resolved.stat().st_mode):
        raise ProposalContractError(f"Product Proposal 不是普通文件：{relative}")
    return resolved


def proposal_sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        raise ProposalContractError(f"无法读取 Product Proposal：{path}") from exc


def _file_sha256(path: Path, *, label: str) -> str:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError as exc:
        raise ProposalContractError(f"无法读取{label}：{path}") from exc


def validate_intake_manifest_data(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProposalContractError("接入前依据 manifest 顶层必须是对象。")
    expected = {"schema_version", "files"}
    unknown = sorted(set(value) - expected)
    missing = sorted(expected - set(value))
    if unknown:
        raise ProposalContractError(
            "接入前依据 manifest 含未知字段：" + "、".join(unknown)
        )
    if missing:
        raise ProposalContractError(
            "接入前依据 manifest 缺少字段：" + "、".join(missing)
        )
    if value.get("schema_version") != INTAKE_MANIFEST_SCHEMA_VERSION:
        raise ProposalContractError(
            f"接入前依据 manifest schema_version 必须是 {INTAKE_MANIFEST_SCHEMA_VERSION}。"
        )
    files = value.get("files")
    if not isinstance(files, list):
        raise ProposalContractError("接入前依据 manifest files 必须是数组。")

    normalized_files: list[dict[str, str]] = []
    seen: set[str] = set()
    for index, item in enumerate(files):
        if not isinstance(item, dict) or set(item) != {"path", "sha256"}:
            raise ProposalContractError(
                f"接入前依据 manifest files[{index}] 必须只含 path 与 sha256。"
            )
        path = _repo_relative_path(
            item.get("path"), label=f"接入前依据 manifest files[{index}].path"
        )
        if path == INTAKE_MANIFEST_RELATIVE_PATH.as_posix():
            raise ProposalContractError("接入前依据 manifest 不能把自身列为接入前文件。")
        if path in seen:
            raise ProposalContractError(f"接入前依据 manifest 路径重复：{path}")
        seen.add(path)
        normalized_files.append({"path": path, "sha256": _sha256(item.get("sha256"))})

    if [item["path"] for item in normalized_files] != sorted(seen):
        raise ProposalContractError("接入前依据 manifest files 必须按 path 唯一排序。")
    return {
        "schema_version": INTAKE_MANIFEST_SCHEMA_VERSION,
        "files": normalized_files,
    }


def load_intake_manifest(repo_root: Path | str) -> dict[str, Any]:
    root = _repo_root(repo_root)
    path = _resolve_repo_regular_file(
        root,
        INTAKE_MANIFEST_RELATIVE_PATH.as_posix(),
        label="接入前依据 manifest",
    )
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ProposalContractError("接入前依据 manifest 无法作为合法 UTF-8 JSON 读取。") from exc
    return validate_intake_manifest_data(value)


def _walk_intake_regular_files(repo_root: Path) -> list[dict[str, str]]:
    files: list[dict[str, str]] = []
    excluded_directories = {
        ".cache",
        ".git",
        ".gradle",
        ".next",
        ".pnpm-store",
        ".pm-workflow",
        ".pytest_cache",
        ".ruff_cache",
        ".tox",
        ".turbo",
        ".venv",
        ".yarn",
        ".worktrees",
        "DerivedData",
        "Pods",
        "__pycache__",
        "bower_components",
        "build",
        "coverage",
        "dist",
        "node_modules",
        "target",
        "vendor",
        "venv",
    }
    for directory, dirnames, filenames in os.walk(repo_root, topdown=True, followlinks=False):
        directory_path = Path(directory)
        safe_dirnames: list[str] = []
        for name in sorted(dirnames):
            if name in excluded_directories:
                continue
            candidate = directory_path / name
            try:
                mode = candidate.lstat().st_mode
            except OSError as exc:
                raise ProposalContractError(
                    f"无法固定接入前文件清单，目录不可读取：{candidate}"
                ) from exc
            if stat.S_ISDIR(mode):
                safe_dirnames.append(name)
        dirnames[:] = safe_dirnames

        for name in sorted(filenames):
            lexical = directory_path / name
            relative = lexical.relative_to(repo_root).as_posix()
            if relative == INTAKE_MANIFEST_RELATIVE_PATH.as_posix():
                continue
            try:
                mode = lexical.lstat().st_mode
            except OSError as exc:
                raise ProposalContractError(
                    f"无法固定接入前文件清单，文件不可读取：{relative}"
                ) from exc
            if not stat.S_ISREG(mode):
                continue
            if lexical.stat().st_size > INTAKE_MANIFEST_MAX_FILE_BYTES:
                continue
            path = _resolve_repo_regular_file(
                repo_root, relative, label="接入前文件"
            )
            files.append(
                {
                    "path": relative,
                    "sha256": _file_sha256(path, label="接入前文件"),
                }
            )
            if len(files) > INTAKE_MANIFEST_MAX_FILES:
                raise ProposalContractError(
                    "接入前可固定文件超过 100000 个；请先移出生成物、依赖或缓存目录。"
                )
    return sorted(files, key=lambda item: item["path"])


def _existing_pmai_markers(repo_root: Path) -> list[str]:
    markers: list[str] = []
    for relative in INTAKE_CAPTURE_BLOCKING_PATHS:
        path = repo_root / relative
        if path.exists() or path.is_symlink():
            markers.append(relative)
    for relative in INTAKE_CAPTURE_MARKER_FILES:
        path = repo_root / relative
        if not path.exists() and not path.is_symlink():
            continue
        if path.is_symlink() or not path.is_file():
            markers.append(relative)
            continue
        try:
            with path.open("r", encoding="utf-8") as handle:
                text = handle.read(1024 * 1024)
        except (OSError, UnicodeDecodeError):
            continue
        if re.search(r"(?:PMAI|/pmai-|\$pmai-)", text, re.IGNORECASE):
            markers.append(relative)
    return markers


def capture_intake_manifest(repo_root: Path | str) -> dict[str, Any]:
    root = _repo_root(repo_root)
    output = root / Path(INTAKE_MANIFEST_RELATIVE_PATH)
    if output.exists() or output.is_symlink():
        raise ProposalContractError(
            "接入前依据 manifest 已存在；不得在 PMAI 写入后重新生成或改写。"
        )
    markers = _existing_pmai_markers(root)
    if markers:
        raise ProposalContractError(
            "检测到 PMAI 已接入标记，拒绝事后生成接入前依据 manifest："
            + "、".join(markers)
        )
    payload = validate_intake_manifest_data(
        {
            "schema_version": INTAKE_MANIFEST_SCHEMA_VERSION,
            "files": _walk_intake_regular_files(root),
        }
    )
    try:
        ensure_directory_beneath(root, output.parent)
        write_text_atomically(
            output,
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            create_mode=0o644,
        )
    except AtomicFileError as exc:
        raise ProposalContractError(f"无法原子写入接入前依据 manifest：{exc}") from exc
    return payload


def _markdown_h2_blocks(text: str) -> list[tuple[str, str]]:
    headings = list(re.finditer(r"^##\s+(.+?)\s*$", text, re.MULTILINE))
    blocks: list[tuple[str, str]] = []
    for index, heading in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        blocks.append((heading.group(1).strip(), text[heading.end() : end]))
    return blocks


def _markdown_h2_sections(text: str) -> dict[str, str]:
    return dict(_markdown_h2_blocks(text))


def _normalized_h2_title(title: str) -> str:
    return re.sub(r"^\d+(?:\.\d+)*[.、]?\s*", "", title).strip()


def _product_sections(text: str) -> dict[str, str]:
    blocks = _markdown_h2_blocks(text)
    duplicate = [
        title
        for title in PRODUCT_BASELINE_SECTIONS
        if sum(
            1 for candidate, _ in blocks if _normalized_h2_title(candidate) == title
        )
        > 1
    ]
    if duplicate:
        raise ProposalContractError(
            "PRODUCT.md 受保护章节不得重复：" + "、".join(duplicate)
        )
    return dict(blocks)


def _meaningful_text(value: str) -> bool:
    candidate = re.sub(r"!?(?:\[([^\]]*)\])\([^)]*\)", r"\1", value)
    candidate = re.sub(r"^[\s>#*+\-|`~]+|[\s`~|]+$", "", candidate).strip()
    candidate = candidate.strip("。.!！?？:：;；,，")
    if not candidate or re.fullmatch(r"(?:<[^>]+>|\{\{[^}]+\}\}|\.{3,}|…+)", candidate):
        return False
    return PLACEHOLDER_ONLY_PATTERN.fullmatch(candidate) is None


def _meaningful_markdown(value: str) -> bool:
    without_comments = re.sub(r"<!--[\s\S]*?-->", "", value)
    lines = without_comments.splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if re.fullmatch(r"#{1,6}\s+.*", stripped):
            continue
        if stripped.startswith("|") and stripped.endswith("|"):
            cells = [cell.strip() for cell in stripped.strip("|").split("|")]
            if cells and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells):
                continue
            if index + 1 < len(lines):
                next_cells = [
                    cell.strip()
                    for cell in lines[index + 1].strip().strip("|").split("|")
                ]
                if next_cells and all(
                    re.fullmatch(r":?-{3,}:?", cell) for cell in next_cells
                ):
                    continue
            if any(_meaningful_text(cell) for cell in cells):
                return True
            continue
        if _meaningful_text(line):
            return True
    return False


def _matching_section_has_content(
    sections: dict[str, str], patterns: tuple[str, ...]
) -> bool:
    for title, body in sections.items():
        normalized = _normalized_h2_title(title)
        if any(re.fullmatch(pattern, normalized, re.IGNORECASE) for pattern in patterns):
            if _meaningful_markdown(body):
                return True
    return False


def _matching_section_body(
    sections: dict[str, str], pattern: str
) -> str | None:
    for title, body in sections.items():
        normalized = _normalized_h2_title(title)
        if re.fullmatch(pattern, normalized, re.IGNORECASE):
            return body
    return None


def _equivalent_baseline_declaration_gaps(
    repo_root: Path,
    product_sections: dict[str, str],
    *,
    extra_git_paths: tuple[str, ...] = (),
) -> list[str]:
    body = _matching_section_body(product_sections, EQUIVALENT_BASELINE_SECTION_PATTERN)
    if body is None or EQUIVALENT_BASELINE_DECLARATION not in body:
        return list(EQUIVALENT_BASELINE_DECLARATION_GAPS)

    gaps: list[str] = []
    evidence_match = re.search(
        r"^\s*(?:[-*+]\s*)?主要依据\s*[：:]\s*(.+?)\s*$",
        body,
        re.MULTILINE,
    )
    evidence_values = re.findall(r"`([^`]+)`", evidence_match.group(1)) if evidence_match else []
    evidence_valid = bool(evidence_values)
    resolved_evidence: dict[str, Path] = {}
    for value in evidence_values:
        try:
            _repo_relative_path(value, label="等价基线主要依据路径")
            if value in {"PRODUCT.md", "PRODUCT-STATE.md"}:
                raise ProposalContractError("PMAI 产品脊柱不能作为接入前主要依据。")
            resolved_evidence[value] = _resolve_repo_regular_file(
                repo_root, value, label="等价基线主要依据"
            )
        except ProposalContractError:
            evidence_valid = False
            break
    if not evidence_valid:
        gaps.append("等价基线主要依据")

    manifest_valid = False
    if evidence_valid:
        try:
            manifest = load_intake_manifest(repo_root)
            intake_hashes = {item["path"]: item["sha256"] for item in manifest["files"]}
            manifest_valid = all(
                intake_hashes.get(value)
                == _file_sha256(resolved_evidence[value], label="等价基线主要依据")
                for value in evidence_values
            ) and _intake_manifest_matches_first_commit(repo_root)
        except ProposalContractError:
            manifest_valid = False
        if not manifest_valid:
            gaps.append(EQUIVALENT_BASELINE_MANIFEST_GAP)

    confirmation_match = re.search(
        r"^\s*(?:[-*+]\s*)?PM\s*确认日期\s*[：:]\s*(\d{4}-\d{2}-\d{2})\s*$",
        body,
        re.MULTILINE | re.IGNORECASE,
    )
    confirmation_valid = False
    if confirmation_match:
        try:
            date.fromisoformat(confirmation_match.group(1))
            confirmation_valid = True
        except ValueError:
            pass
    if not confirmation_valid:
        gaps.append("等价基线 PM 确认日期")
    if evidence_valid and manifest_valid and not _git_paths_are_tracked_and_clean(
        repo_root,
        [
            "PRODUCT.md",
            INTAKE_MANIFEST_RELATIVE_PATH.as_posix(),
            *evidence_values,
            *extra_git_paths,
        ],
    ):
        gaps.append(EQUIVALENT_BASELINE_GIT_GAP)
    return gaps


def equivalent_baseline_gaps(repo_root: Path | str) -> list[str]:
    root = _repo_root(repo_root)
    try:
        product_path = _resolve_repo_regular_file(root, "PRODUCT.md", label="PRODUCT.md")
        product_text = product_path.read_text(encoding="utf-8")
        product_sections = _product_sections(product_text)
    except (OSError, UnicodeDecodeError, ProposalContractError):
        return [EQUIVALENT_BASELINE_FILE_GAP]

    gaps = [
        label
        for label, patterns in EQUIVALENT_BASELINE_CHECKS
        if not _matching_section_has_content(product_sections, patterns)
    ]

    has_mvp = _matching_section_has_content(product_sections, (r"MVP(?:\s*Case|\s*结果|\s*范围)?",))
    has_current_result = False
    state_used = False
    state_path = root / "PRODUCT-STATE.md"
    if state_path.exists() or state_path.is_symlink():
        try:
            safe_state_path = _resolve_repo_regular_file(
                root, "PRODUCT-STATE.md", label="PRODUCT-STATE.md"
            )
            state_text = safe_state_path.read_text(encoding="utf-8")
            has_current_result = _matching_section_has_content(
                _markdown_h2_sections(state_text), CURRENT_RESULT_SECTION_PATTERNS
            )
            state_used = not has_mvp and has_current_result
        except (OSError, UnicodeDecodeError, ProposalContractError):
            gaps.append(EQUIVALENT_BASELINE_FILE_GAP)
    if not has_mvp and not has_current_result:
        gaps.append("MVP 或当前产品结果")
    gaps.extend(
        _equivalent_baseline_declaration_gaps(
            root,
            product_sections,
            extra_git_paths=("PRODUCT-STATE.md",) if state_used else (),
        )
    )
    return list(dict.fromkeys(gaps))


def _proposal_header(text: str) -> dict[str, str]:
    header = _proposal_header_fields(text)
    if not re.fullmatch(r"v[1-9][0-9]*", header["版本"]):
        raise ProposalContractError("Product Proposal 版本必须使用 v1、v2 等格式。")
    parsed_dates: dict[str, date] = {}
    for field in ("日期", "证据截至"):
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", header[field]):
            raise ProposalContractError(f"Product Proposal {field}必须使用有效的 YYYY-MM-DD 日期。")
        try:
            parsed_dates[field] = date.fromisoformat(header[field])
        except ValueError as exc:
            raise ProposalContractError(
                f"Product Proposal {field}必须使用有效的 YYYY-MM-DD 日期。"
            ) from exc
    if parsed_dates["证据截至"] > parsed_dates["日期"]:
        raise ProposalContractError("Product Proposal 证据截至不能晚于文档日期。")
    if header["状态"] != "当前":
        raise ProposalContractError("当前 Product Proposal 的状态头不是“当前”。")
    if not _meaningful_markdown(header["支持的决定"]):
        raise ProposalContractError("Product Proposal 的“支持的决定”仍是空白或占位内容。")
    return header


def _proposal_header_fields(text: str) -> dict[str, str]:
    header: dict[str, str] = {}
    counts: dict[str, int] = {}
    for match in re.finditer(r"^>\s*([^：:\n]+?)\s*[：:]\s*(.*?)\s*$", text, re.MULTILINE):
        label = match.group(1).strip().strip("*")
        if label in PROPOSAL_HEADER_FIELDS:
            counts[label] = counts.get(label, 0) + 1
            header[label] = match.group(2).strip()
    duplicate = [label for label in PROPOSAL_HEADER_FIELDS if counts.get(label, 0) > 1]
    if duplicate:
        raise ProposalContractError(
            "Product Proposal 文档头字段不得重复：" + "、".join(duplicate)
        )
    missing = [label for label in PROPOSAL_HEADER_FIELDS if not header.get(label)]
    if missing:
        raise ProposalContractError("Product Proposal 文档头缺少字段：" + "、".join(missing))
    return header


def _superseded_path_from_header(header: dict[str, str]) -> str:
    value = header["取代"].strip()
    if value.startswith("`") and value.endswith("`"):
        value = value[1:-1].strip()
    try:
        return _proposal_relative_path(value)
    except ProposalContractError as exc:
        raise ProposalContractError(
            "修订版 Product Proposal 的“取代”必须只写旧版本仓内路径。"
        ) from exc


def _proposal_index_rows_from_text(text: str) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not (stripped.startswith("|") and stripped.endswith("|")):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if len(cells) < 3:
            continue
        link = re.search(r"\[[^\]]+\]\(\s*(?:<([^>]+)>|([^\s)]+))\s*\)", cells[0])
        if link is None:
            continue
        target = (link.group(1) or link.group(2)).strip()
        target_path = PurePosixPath(target)
        if target_path.parts[:2] != ("docs", "proposals"):
            target_path = PurePosixPath("docs", "proposals") / target_path
        try:
            relative = _proposal_relative_path(target_path.as_posix())
        except ProposalContractError:
            continue
        status = cells[2].strip().strip("*`").strip()
        rows.append((relative, status))
    return rows


def _proposal_index_rows(repo_root: Path) -> list[tuple[str, str]]:
    try:
        index = _resolve_repo_regular_file(
            repo_root,
            "docs/proposals/INDEX.md",
            label="docs/proposals/INDEX.md",
        )
        text = index.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError, ProposalContractError) as exc:
        raise ProposalContractError(
            "docs/proposals/INDEX.md 必须是可读取的仓库内普通文件。"
        ) from exc
    return _proposal_index_rows_from_text(text)


def _validate_current_index(repo_root: Path, current_path: str) -> None:
    rows = _proposal_index_rows(repo_root)
    current_rows = [path for path, status in rows if status == "当前"]
    if current_rows != [current_path]:
        raise ProposalContractError(
            "docs/proposals/INDEX.md 必须且只能把合同指向的版本标为“当前”。"
        )
    statuses = [status for path, status in rows if path == current_path]
    if statuses != ["当前"]:
        raise ProposalContractError(
            "docs/proposals/INDEX.md 必须只登记一次合同指向的当前版本。"
        )


def _validate_revision_consistency(
    repo_root: Path,
    *,
    current_path: str,
    superseded_id: str,
    superseded_path: str,
) -> None:
    old_path = resolve_proposal_path(repo_root, superseded_path)
    try:
        old_text = old_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ProposalContractError(
            f"被取代的 Product Proposal 无法按 UTF-8 读取：{superseded_path}"
        ) from exc
    old_header = _proposal_header_fields(old_text)
    if old_header["Proposal ID"] != superseded_id:
        raise ProposalContractError(
            f"被取代 Proposal 的文档头 ID 必须是 {superseded_id}。"
        )
    expected_status = rf"已被\s+`?{re.escape(current_path)}`?\s+取代"
    if re.fullmatch(expected_status, old_header["状态"]) is None:
        raise ProposalContractError(
            f"旧 Proposal 必须标为已被当前版本取代：{current_path}"
        )

    rows = _proposal_index_rows(repo_root)
    _validate_current_index(repo_root, current_path)
    old_statuses = [status for path, status in rows if path == superseded_path]
    if old_statuses != ["已取代"]:
        raise ProposalContractError(
            "docs/proposals/INDEX.md 必须把旧版本唯一标为“已取代”。"
        )


def _git(repo_root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", "-C", str(repo_root), *args],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        raise ProposalContractError("无法运行 Git，当前 Proposal 不能生效。") from exc


def _git_bytes(repo_root: Path, *args: str) -> subprocess.CompletedProcess[bytes]:
    try:
        return subprocess.run(
            ["git", "-C", str(repo_root), *args],
            check=False,
            capture_output=True,
        )
    except OSError as exc:
        raise ProposalContractError("无法运行 Git，当前 Proposal 不能生效。") from exc


def _contract_effective_commit(repo_root: Path) -> str:
    contract_commit = _git(
        repo_root,
        "log",
        "-1",
        "--format=%H",
        "--",
        f":(literal){CONTRACT_RELATIVE_PATH.as_posix()}",
    )
    commit = contract_commit.stdout.strip().lower()
    if contract_commit.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40,64}", commit):
        raise ProposalContractError("无法找到 proposal.json 对应的生效提交。")
    return commit


def _git_regular_blob_at_commit(
    repo_root: Path,
    commit: str,
    relative: str,
    *,
    label: str,
) -> bytes:
    _repo_relative_path(relative, label=f"{label}路径")
    tree = _git_bytes(
        repo_root,
        "ls-tree",
        "-z",
        commit,
        "--",
        f":(literal){relative}",
    )
    if tree.returncode != 0:
        raise ProposalContractError(f"无法读取{label}在合同生效提交中的文件类型。")
    entries = [entry for entry in tree.stdout.split(b"\0") if entry]
    if len(entries) != 1 or b"\t" not in entries[0]:
        raise ProposalContractError(f"合同生效提交中缺少{label}：{relative}")
    metadata, encoded_path = entries[0].split(b"\t", 1)
    fields = metadata.split()
    if len(fields) != 3 or fields[0] not in {b"100644", b"100755"} or fields[1] != b"blob":
        raise ProposalContractError(f"合同生效提交中的{label}不是普通文件：{relative}")
    try:
        decoded_path = encoded_path.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ProposalContractError(f"合同生效提交中的{label}路径不是 UTF-8。") from exc
    if decoded_path != relative:
        raise ProposalContractError(f"合同生效提交中的{label}路径不一致：{relative}")
    blob = _git_bytes(repo_root, "cat-file", "blob", fields[2].decode("ascii"))
    if blob.returncode != 0:
        raise ProposalContractError(f"无法读取{label}在合同生效提交中的正文。")
    return blob.stdout


def _require_current_file_matches_commit_blob(
    repo_root: Path,
    *,
    commit: str,
    relative: str,
    label: str,
) -> None:
    path = _resolve_repo_regular_file(repo_root, relative, label=label)
    try:
        current = path.read_bytes()
    except OSError as exc:
        raise ProposalContractError(f"无法读取{label}：{relative}") from exc
    accepted = _git_regular_blob_at_commit(
        repo_root, commit, relative, label=label
    )
    if current != accepted:
        raise ProposalContractError(
            f"{label}在合同生效提交后发生漂移：{relative}"
        )


def _intake_manifest_matches_first_commit(repo_root: Path) -> bool:
    relative = INTAKE_MANIFEST_RELATIVE_PATH.as_posix()
    added = _git(
        repo_root,
        "log",
        "--diff-filter=A",
        "--reverse",
        "--format=%H",
        "--",
        f":(literal){relative}",
    )
    commits = [line.strip().lower() for line in added.stdout.splitlines() if line.strip()]
    if added.returncode != 0 or not commits or not re.fullmatch(
        r"[0-9a-f]{40,64}", commits[0]
    ):
        return False
    try:
        path = _resolve_repo_regular_file(
            repo_root, relative, label="接入前依据 manifest"
        )
        return path.read_bytes() == _git_regular_blob_at_commit(
            repo_root,
            commits[0],
            relative,
            label="接入前依据 manifest",
        )
    except (OSError, ProposalContractError):
        return False


def _index_rows_at_commit(repo_root: Path, commit: str) -> list[tuple[str, str]]:
    blob = _git_regular_blob_at_commit(
        repo_root,
        commit,
        "docs/proposals/INDEX.md",
        label="docs/proposals/INDEX.md",
    )
    try:
        text = blob.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ProposalContractError(
            "合同生效提交中的 docs/proposals/INDEX.md 不是合法 UTF-8。"
        ) from exc
    return _proposal_index_rows_from_text(text)


def _require_existing_proposal_history_unchanged_before_supersede(
    repo_root: Path,
    *,
    contract_commit: str,
) -> None:
    head = _git_head(repo_root)
    accepted_index = _git_regular_blob_at_commit(
        repo_root,
        contract_commit,
        "docs/proposals/INDEX.md",
        label="docs/proposals/INDEX.md",
    )
    head_index = _git_regular_blob_at_commit(
        repo_root,
        head,
        "docs/proposals/INDEX.md",
        label="docs/proposals/INDEX.md",
    )
    if head_index != accepted_index:
        raise ProposalContractError(
            "docs/proposals/INDEX.md 在上一份合同生效后已有已提交漂移，不能继续 supersede。"
        )
    for relative in dict.fromkeys(
        path for path, _ in _index_rows_at_commit(repo_root, contract_commit)
    ):
        current = _git_regular_blob_at_commit(
            repo_root, head, relative, label="Product Proposal 历史版本"
        )
        accepted = _git_regular_blob_at_commit(
            repo_root,
            contract_commit,
            relative,
            label="Product Proposal 历史版本",
        )
        if current != accepted:
            raise ProposalContractError(
                "Product Proposal 历史版本在上一份合同生效后已有已提交漂移，"
                f"不能继续 supersede：{relative}"
            )


def _require_all_historical_proposals_match_activation(
    repo_root: Path,
    *,
    contract_commit: str,
    current_path: str,
) -> None:
    rows = _proposal_index_rows(repo_root)
    historical_paths = dict.fromkeys(path for path, _ in rows if path != current_path)
    for relative in historical_paths:
        _require_current_file_matches_commit_blob(
            repo_root,
            commit=contract_commit,
            relative=relative,
            label="Product Proposal 历史版本",
        )


def _git_paths_are_tracked_and_clean(repo_root: Path, paths: list[str]) -> bool:
    """Return whether baseline evidence is committed and unchanged in this repo."""
    try:
        top_level = _git(repo_root, "rev-parse", "--show-toplevel")
        if top_level.returncode != 0 or Path(top_level.stdout.strip()).resolve() != repo_root:
            return False
        head = _git(repo_root, "rev-parse", "--verify", "HEAD")
        if head.returncode != 0:
            return False
        pathspecs = [f":(literal){path}" for path in paths]
        tracked = _git(repo_root, "ls-files", "--error-unmatch", "--", *pathspecs)
        if tracked.returncode != 0:
            return False
        dirty = _git(
            repo_root,
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--",
            *pathspecs,
        )
        return dirty.returncode == 0 and not dirty.stdout
    except (OSError, ProposalContractError):
        return False


def _git_head(repo_root: Path) -> str:
    top_level = _git(repo_root, "rev-parse", "--show-toplevel")
    if top_level.returncode != 0:
        raise ProposalContractError(
            "当前目录不是 Git 仓库；Proposal 合同必须提交后才能生效。"
        )
    try:
        resolved_top_level = Path(top_level.stdout.strip()).resolve()
    except OSError as exc:
        raise ProposalContractError("无法确认 Git 仓库根目录。") from exc
    if resolved_top_level != repo_root:
        raise ProposalContractError("Proposal 合同必须位于当前 Git 仓库根目录。")
    head = _git(repo_root, "rev-parse", "--verify", "HEAD")
    if head.returncode != 0 or not re.fullmatch(r"[0-9a-fA-F]{40,64}", head.stdout.strip()):
        raise ProposalContractError(
            "Git 仓库还没有 HEAD；请先完成项目初始化提交，再确认 Proposal。"
        )
    return head.stdout.strip().lower()


def _require_integration_branch(repo_root: Path) -> None:
    branch = _git(repo_root, "symbolic-ref", "--quiet", "--short", "HEAD")
    current = branch.stdout.strip()
    if branch.returncode != 0 or current not in ("main", "master"):
        label = current or "detached HEAD"
        raise ProposalContractError(
            "Product Proposal 只能在 main/master 主线定稿；"
            f"当前是 {label}。active worktree build 请先通过 "
            "replan-work.py --route proposal 收口并回到主线重试。"
        )


def _attached_worktree_roots(repo_root: Path) -> list[Path]:
    listed = _git(repo_root, "worktree", "list", "--porcelain", "-z")
    if listed.returncode != 0:
        raise ProposalContractError(
            "无法扫描主仓与 attached worktrees；不能确认 active build 已全部收口。"
        )

    roots: list[Path] = []
    seen: set[Path] = set()
    for field in listed.stdout.split("\0"):
        if not field.startswith("worktree "):
            continue
        raw_path = field.removeprefix("worktree ")
        try:
            root = Path(raw_path).resolve(strict=True)
        except OSError as exc:
            raise ProposalContractError(
                f"attached worktree 无法读取，不能确认 active build 已收口：{raw_path}"
            ) from exc
        if not root.is_dir():
            raise ProposalContractError(
                f"attached worktree 不是目录，不能确认 active build 已收口：{raw_path}"
            )
        if root not in seen:
            roots.append(root)
            seen.add(root)

    if repo_root not in seen:
        raise ProposalContractError(
            "Git worktree 清单未包含当前主仓；不能确认 active build 已全部收口。"
        )
    return roots


def _active_builds_across_worktrees(repo_root: Path) -> list[dict[str, str]]:
    active: list[dict[str, str]] = []
    for worktree_root in _attached_worktree_roots(repo_root):
        modules_root = worktree_root / "docs" / "modules"
        if modules_root.is_symlink():
            raise ProposalContractError(
                f"模块目录不能是 symlink，无法安全扫描 active build：{modules_root}"
            )
        if not modules_root.exists():
            continue
        if not modules_root.is_dir():
            raise ProposalContractError(
                f"模块目录不是可安全扫描的普通目录：{modules_root}"
            )
        try:
            module_dirs = sorted(modules_root.iterdir(), key=lambda item: item.name)
        except OSError as exc:
            raise ProposalContractError(
                f"无法扫描模块目录，不能确认 active build 已收口：{modules_root}"
            ) from exc

        for module_dir in module_dirs:
            if module_dir.is_symlink():
                raise ProposalContractError(
                    f"模块目录不能是 symlink，无法安全扫描 active build：{module_dir}"
                )
            if not module_dir.is_dir():
                continue
            metadata_path = module_dir / ".work-meta.json"
            if metadata_path.is_symlink():
                raise ProposalContractError(
                    f"活动工作元数据必须是普通文件：{metadata_path}"
                )
            if not metadata_path.exists():
                continue
            try:
                is_regular = stat.S_ISREG(metadata_path.stat().st_mode)
            except OSError as exc:
                raise ProposalContractError(
                    f"无法检查活动工作元数据：{metadata_path}"
                ) from exc
            if not is_regular:
                raise ProposalContractError(
                    f"活动工作元数据必须是普通文件：{metadata_path}"
                )
            try:
                metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ProposalContractError(
                    f"无法读取活动工作元数据，不能确认 active build 已收口：{metadata_path}"
                ) from exc
            if not isinstance(metadata, dict):
                raise ProposalContractError(
                    f"活动工作元数据必须是 JSON 对象：{metadata_path}"
                )

            build = metadata.get("build")
            build_data = build if isinstance(build, dict) else {}
            lifecycle_values = {
                str(value)
                for value in (
                    metadata.get("lifecycle_state"),
                    build_data.get("lifecycle_state"),
                )
                if value
            }
            blocked_lifecycles = sorted(lifecycle_values & ACTIVE_BUILD_LIFECYCLES)
            if not blocked_lifecycles:
                continue

            declared_mode = str(build_data.get("mode") or "")
            if declared_mode not in {"main", "worktree"}:
                declared_mode = "main" if worktree_root == repo_root else "worktree"
            active.append(
                {
                    "id": str(metadata.get("id") or module_dir.name),
                    "lifecycle": "/".join(blocked_lifecycles),
                    "mode": declared_mode,
                    "module_dir": str(module_dir),
                    "location": "主仓" if worktree_root == repo_root else "attached worktree",
                }
            )
    return active


def _require_no_active_builds_before_accept(repo_root: Path) -> None:
    active = _active_builds_across_worktrees(repo_root)
    if not active:
        return

    details = "；".join(
        f"{item['id']} [{item['lifecycle']}, {item['mode']}, {item['location']}] "
        f"({item['module_dir']})"
        for item in active
    )
    guidance: list[str] = []
    if any(item["mode"] == "worktree" for item in active):
        guidance.append(
            "worktree 候选先在对应模块目录运行 "
            '`python3 "$PMAI_HOME/scripts/replan-work.py" "$ACTIVE_WORK_DIR" '
            "--route proposal`"
        )
    if any(item["mode"] == "main" for item in active):
        guidance.append(
            "main mode 候选也运行同一 replan-work.py --route proposal 入口；"
            "入口只清活动状态并保留已经在 main 的实现"
        )
    raise ProposalContractError(
        "检测到尚未收口的 active build，拒绝改写 proposal.json："
        + details
        + "。"
        + "；".join(guidance)
        + "，完成后再重试。"
    )


def _proposal_git_paths(metadata: dict[str, Any], text: str) -> list[str]:
    paths = [
        CONTRACT_RELATIVE_PATH.as_posix(),
        metadata["path"],
        "PRODUCT.md",
        "docs/proposals/INDEX.md",
    ]
    if metadata["supersedes"] is not None:
        paths.extend(
            [
                _superseded_path_from_header(_proposal_header(text)),
                "docs/proposals/INDEX.md",
            ]
        )
    return list(dict.fromkeys(paths))


def _validate_git_currentness(
    repo_root: Path, metadata: dict[str, Any], text: str
) -> str:
    _git_head(repo_root)
    paths = _proposal_git_paths(metadata, text)
    pathspecs = [f":(literal){path}" for path in paths]

    tracked = _git(repo_root, "ls-files", "--error-unmatch", "--", *pathspecs)
    if tracked.returncode != 0:
        raise ProposalContractError(
            "当前 Proposal 原子文件尚未全部进入 Git；请完成同一提交后重试。"
        )
    dirty = _git(
        repo_root,
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
        "--",
        *pathspecs,
    )
    if dirty.returncode != 0:
        raise ProposalContractError("无法确认当前 Proposal 的 Git 状态。")
    if dirty.stdout:
        raise ProposalContractError(
            "当前 Proposal 原子文件仍有未提交改动；提交成功前不能作为下游依据。"
        )

    commit = _contract_effective_commit(repo_root)
    if metadata["schema_version"] < ATOMIC_SCHEMA_VERSION:
        return commit

    changed = _git(
        repo_root,
        "diff-tree",
        "--root",
        "--no-commit-id",
        "--name-only",
        "-r",
        "-z",
        commit,
    )
    if changed.returncode != 0:
        raise ProposalContractError("无法核验 Proposal 原子提交内容。")
    changed_paths = {item for item in changed.stdout.split("\0") if item}
    missing = [path for path in paths if path not in changed_paths]
    if missing:
        raise ProposalContractError(
            "proposal.json 未与全部产品基线文件在同一提交生效：" + "、".join(missing)
        )
    return commit


def validate_proposal_document(
    text: str,
    *,
    expected_id: str,
    superseded_path: str | None,
    require_supersedes: bool = False,
) -> dict[str, str]:
    header = _proposal_header(text)
    if header["Proposal ID"] != expected_id:
        raise ProposalContractError(
            f"Product Proposal 文档头 ID 与合同不一致：应为 {expected_id}。"
        )
    if superseded_path is None and not require_supersedes:
        if header["取代"] != "无":
            raise ProposalContractError("首个 Product Proposal 的“取代”必须写“无”。")
    elif superseded_path is not None:
        if _superseded_path_from_header(header) != superseded_path:
            raise ProposalContractError(
                f"Product Proposal 文档头必须明确取代旧版本：{superseded_path}"
            )
    elif require_supersedes and header["取代"] == "无":
        raise ProposalContractError("修订版 Product Proposal 必须在文档头写明被取代版本。")

    numbered: dict[int, tuple[str, str]] = {}
    for title, body in _markdown_h2_blocks(text):
        match = re.fullmatch(r"(\d+)\.\s*(.+)", title)
        if not match:
            continue
        number = int(match.group(1))
        if number in numbered:
            raise ProposalContractError(f"Product Proposal 存在重复章节：{number}。")
        numbered[number] = (match.group(2).strip(), body)

    missing_sections: list[str] = []
    for number, title_pattern in PROPOSAL_SECTION_PATTERNS.items():
        item = numbered.get(number)
        if item is None or re.fullmatch(title_pattern, item[0]) is None:
            missing_sections.append(str(number))
            continue
        if not _meaningful_markdown(item[1]):
            raise ProposalContractError(f"Product Proposal 第 {number} 节没有有效内容。")
    if missing_sections:
        raise ProposalContractError(
            "Product Proposal 缺少或误命名固定章节：" + "、".join(missing_sections)
        )

    return extract_handoff(text)


def _product_baseline_hash_from_text(text: str, proposal_path: str) -> str:
    if PROPOSAL_REQUIRED_MARKER in text:
        raise ProposalContractError(
            "PRODUCT.md 仍标记 Product Proposal 待完成；请先同步精简产品基线并移除标记。"
        )
    sections = _product_sections(text)
    current_proposal = sections.get("当前 Product Proposal", "")
    current_proposal_without_comments = re.sub(
        r"<!--[\s\S]*?-->", "", current_proposal
    )
    if proposal_path not in current_proposal_without_comments:
        raise ProposalContractError(
            f"PRODUCT.md 的“当前 Product Proposal”尚未引用当前版本：{proposal_path}"
        )
    missing = [
        title
        for title in PRODUCT_BASELINE_SECTIONS
        if title not in sections or not _meaningful_markdown(sections[title])
    ]
    if missing:
        raise ProposalContractError(
            "PRODUCT.md 尚未同步完整精简产品基线：" + "、".join(missing)
        )
    protected = [(title, sections[title]) for title in PRODUCT_BASELINE_SECTIONS]
    canonical = json.dumps(protected, ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _validate_product_baseline(repo_root: Path, proposal_path: str) -> str:
    product = _resolve_repo_regular_file(repo_root, "PRODUCT.md", label="PRODUCT.md")
    try:
        text = product.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ProposalContractError("PRODUCT.md 无法读取，不能确认产品基线同步完成。") from exc
    return _product_baseline_hash_from_text(text, proposal_path)


def extract_handoff(text: str) -> dict[str, str]:
    headings = list(re.finditer(r"^##\s+(.+?)\s*$", text, re.MULTILINE))
    section = ""
    for index, heading in enumerate(headings):
        title = re.sub(r"^\d+(?:\.\d+)?[.、]?\s*", "", heading.group(1)).strip()
        if title != "下游交接摘要":
            continue
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        section = text[heading.end() : end]
        break
    if not section:
        raise ProposalContractError("当前 Product Proposal 缺少固定的“下游交接摘要”。")

    values: dict[str, str] = {}
    for match in re.finditer(
        r"^\s*-\s+\*\*(.+?)\*\*\s*[：:]\s*(.+?)\s*$", section, re.MULTILINE
    ):
        label = re.sub(r"\s+", " ", match.group(1).strip())
        if label in HANDOFF_FIELDS:
            content = match.group(2).strip()
            if _meaningful_markdown(content):
                values[HANDOFF_FIELDS[label]] = content
    missing = [field for field in HANDOFF_FIELDS.values() if not values.get(field)]
    if missing:
        labels = [label for label, field in HANDOFF_FIELDS.items() if field in missing]
        raise ProposalContractError("下游交接摘要缺少字段：" + "、".join(labels))
    return values


def validate_current_proposal(repo_root: Path | str) -> dict[str, Any]:
    root = _repo_root(repo_root)
    metadata = load_contract_metadata(root)
    actual_product_hash = _validate_product_baseline(root, metadata["path"])
    if (
        metadata["schema_version"] == SCHEMA_VERSION
        and actual_product_hash != metadata[PRODUCT_HASH_FIELD]
    ):
        raise ProposalContractError(
            "PRODUCT.md 产品基线在 Proposal 确认后发生漂移；"
            "请回到 /pmai-proposal 生成并确认新版本。"
        )
    proposal = resolve_proposal_path(root, metadata["path"])
    actual_hash = proposal_sha256(proposal)
    if actual_hash != metadata["hash"]:
        raise ProposalContractError(
            "当前 Product Proposal 在确认后发生正文漂移；请回到 /pmai-proposal 生成并确认新版本。"
        )
    try:
        text = proposal.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ProposalContractError(f"当前 Product Proposal 无法按 UTF-8 读取：{metadata['path']}") from exc
    handoff = validate_proposal_document(
        text,
        expected_id=metadata["id"],
        superseded_path=None,
        require_supersedes=metadata["supersedes"] is not None,
    )
    _validate_current_index(root, metadata["path"])
    if metadata["supersedes"] is not None:
        header = _proposal_header(text)
        _validate_revision_consistency(
            root,
            current_path=metadata["path"],
            superseded_id=metadata["supersedes"],
            superseded_path=_superseded_path_from_header(header),
        )
    contract_commit = _validate_git_currentness(root, metadata, text)
    _require_current_file_matches_commit_blob(
        root,
        commit=contract_commit,
        relative="docs/proposals/INDEX.md",
        label="docs/proposals/INDEX.md",
    )
    if metadata["schema_version"] < SCHEMA_VERSION:
        historical_product = _git_regular_blob_at_commit(
            root, contract_commit, "PRODUCT.md", label="PRODUCT.md"
        )
        try:
            historical_text = historical_product.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise ProposalContractError(
                "合同生效提交中的 PRODUCT.md 不是合法 UTF-8。"
            ) from exc
        historical_product_hash = _product_baseline_hash_from_text(
            historical_text, metadata["path"]
        )
        if actual_product_hash != historical_product_hash:
            raise ProposalContractError(
                "PRODUCT.md 产品基线在旧版 Proposal 合同生效后发生漂移；"
                "旧合同继续只读兼容，但必须回到 /pmai-proposal 生成新版本。"
            )
    if metadata["supersedes"] is not None:
        _require_all_historical_proposals_match_activation(
            root,
            contract_commit=contract_commit,
            current_path=metadata["path"],
        )
    return {**metadata, "handoff": handoff}


def proposal_is_required(repo_root: Path | str) -> bool:
    root = _repo_root(repo_root)
    try:
        product = _resolve_repo_regular_file(root, "PRODUCT.md", label="PRODUCT.md")
        return PROPOSAL_REQUIRED_MARKER in product.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError, ProposalContractError):
        return False


def proposal_state(repo_root: Path | str) -> dict[str, Any]:
    root = _repo_root(repo_root)
    path = contract_path(root)
    if not path.exists():
        if proposal_is_required(root):
            return {
                "state": "required",
                "reason": "new_project",
                "gaps": [],
                "proposal": None,
            }
        gaps = equivalent_baseline_gaps(root)
        if gaps:
            return {
                "state": "required",
                "reason": "incomplete_equivalent_baseline",
                "gaps": gaps,
                "proposal": None,
            }
        return {
            "state": "equivalent_baseline",
            "reason": "complete_equivalent_baseline",
            "gaps": [],
            "proposal": None,
        }
    try:
        current = validate_current_proposal(root)
    except ProposalContractError as exc:
        return {"state": "invalid", "reason": str(exc), "proposal": None}
    return {"state": "accepted", "proposal": current}


def accept_proposal(
    repo_root: Path | str,
    *,
    proposal_id: str,
    proposal: str,
    supersedes: str | None = None,
    accepted_at: str | None = None,
) -> dict[str, Any]:
    root = _repo_root(repo_root)
    normalized_id = _proposal_id(proposal_id)
    relative = _proposal_relative_path(proposal)
    proposal_path = resolve_proposal_path(root, relative)
    try:
        text = proposal_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise ProposalContractError(f"Product Proposal 无法按 UTF-8 读取：{relative}") from exc
    content_hash = proposal_sha256(proposal_path)
    output = contract_path(root)
    existing: dict[str, Any] | None = None
    if output.exists():
        existing = load_contract_metadata(root)
        if normalized_id == existing["id"]:
            if (
                relative == existing["path"]
                and content_hash == existing["hash"]
                and supersedes == existing["supersedes"]
            ):
                validate_current_proposal(root)
                return existing
            raise ProposalContractError(
                "已确认 Proposal 不得原地改写；请创建完整新版本并使用新的 id。"
            )
        if supersedes != existing["id"]:
            raise ProposalContractError(
                f"新 Proposal 必须显式 supersede 当前版本 {existing['id']}。"
            )
        if relative == existing["path"]:
            raise ProposalContractError("新 Proposal 必须使用新文件，不能覆盖当前版本正文。")
        _require_existing_proposal_history_unchanged_before_supersede(
            root,
            contract_commit=_contract_effective_commit(root),
        )
    elif supersedes is not None:
        _proposal_id(supersedes, "supersedes")
        raise ProposalContractError(
            "没有可被取代的当前 Proposal 合同，不能使用 --supersedes。"
        )

    superseded_path = existing["path"] if existing is not None else None
    handoff = validate_proposal_document(
        text,
        expected_id=normalized_id,
        superseded_path=superseded_path,
    )
    if not handoff:
        raise ProposalContractError("Product Proposal 缺少可消费的下游交接摘要。")
    _validate_current_index(root, relative)
    product_hash = _validate_product_baseline(root, relative)
    if existing is not None:
        _validate_revision_consistency(
            root,
            current_path=relative,
            superseded_id=existing["id"],
            superseded_path=existing["path"],
        )
    _git_head(root)
    _require_integration_branch(root)

    timestamp = accepted_at or datetime.now(timezone.utc).astimezone().isoformat(
        timespec="seconds"
    )
    payload = validate_contract_data(
        {
            "schema_version": SCHEMA_VERSION,
            "id": normalized_id,
            "status": VALID_STATUS,
            "path": relative,
            "hash": content_hash,
            PRODUCT_HASH_FIELD: product_hash,
            "accepted_at": timestamp,
            "supersedes": supersedes,
        }
    )
    _require_no_active_builds_before_accept(root)
    ensure_directory_beneath(root, output.parent)
    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    try:
        write_text_atomically(output, rendered, create_mode=0o644)
    except AtomicFileError as exc:
        raise ProposalContractError(f"无法原子写入 proposal.json：{exc}") from exc
    return payload
