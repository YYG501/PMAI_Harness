#!/usr/bin/env python3
"""Read-only PMAI consumer repository topology and lifecycle diagnostics."""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _lib.project_definition import (  # noqa: E402
    ProjectDefinitionError,
    load_project_definition,
    parse_yaml_subset,
)
from _lib.consumer_entry import (  # noqa: E402
    ConsumerEntryError,
    plan_consumer_entry,
)
from _lib.proposal import proposal_state  # noqa: E402
from _lib.work_contract import (  # noqa: E402
    WorkContractError,
    normalize_work_contract,
)


SCHEMA_VERSION = 1
CURRENT_LAYOUT_VERSION = 1
LIFECYCLE_ORDER = {
    "designing": 1,
    "ready_to_build": 2,
    "building": 3,
    "iterating": 4,
    "final_check": 5,
    "landed": 6,
    "documenting": 7,
    "complete": 8,
}
BUILD_STATES = {"building", "iterating", "final_check", "landed", "documenting", "complete"}
VALID_BUILD_MODES = {"main", "worktree"}
VALID_EXECUTORS = {"claude-code", "codex", "cursor-agent", "kimi-code", "opencode", "manual", "native"}
VALID_DOCS_STATUSES = {"pending", "complete", "failed"}
TRIO = ("discussion.md", "decisions.md", "spec.md")
PROJECT_REQUIRED_FILES = (
    "PRODUCT.md",
    "PRODUCT-STATE.md",
    "DESIGN.md",
    "PRODUCT-RULES.md",
    "TODO.md",
)
FRAMEWORK_MANAGED_FILES = (
    ".gitignore",
    "AGENTS.md",
    "CLAUDE.md",
    "docs/INDEX.md",
    "docs/modules/INDEX.md",
    "docs/engineering/INDEX.md",
    "docs/deliverables/INDEX.md",
    "docs/proposals/INDEX.md",
    ".pm-workflow/config.yml",
    "templates/lark-publish.json.tmpl",
)
PROJECT_REQUIRED_DIRS = (
    "docs/modules",
)
FRAMEWORK_MANAGED_DIRS = (
    ".pm-workflow",
    "docs/inputs",
    "docs/engineering",
    "docs/deliverables",
    "docs/proposals",
    "docs/decisions",
)
DEFAULT_ARCHIVE_DIR = "docs/archive"
VALID_MODULE_STATES = {"current", "legacy", "retired", "split"}
VALID_LEGACY_FORMATS = {"spec_decisions", "merged_spec"}
FINDING_FRAMEWORK_SYNC = "framework_managed_sync"
FINDING_LEGACY = "legacy_compatible"
FINDING_COMPATIBILITY = "compatibility_declaration_required"
FINDING_INVALID = "project_content_invalid"
FINDING_ADVISORY = "project_advisory"
HOST_PATHS = (
    ".claude/settings.json",
    ".codex/hooks.json",
)
LEGACY_HOST_PATHS = (".opencode/commands", "opencode.json")
IGNORE_PROBES = (
    ".runs/doctor-probe",
    ".worktrees/doctor-probe",
    ".pm-workflow/context/doctor-probe",
    ".claude/lark-publish.json",
)
MOCKUP_STATUSES = {"活跃", "待合并", "已退役"}
MOCKUP_REQUIRED_KEYS = {
    "path": str,
    "requirement": str,
    "explores": str,
    "good_parts": str,
    "status": str,
    "round": str,
    "featured": bool,
}
MOCKUP_CURRENT_KEYS = {
    "approach": str,
    "best_for": str,
    "tradeoffs": str,
    "round_goal": str,
    "created_at": str,
    "updated_at": str,
}
MOCKUP_QUALITY_SCHEMA_VERSION = 2
MOCKUP_QUALITY_KEYS = {
    "design_basis": str,
    "visual_audit": str,
}


def _valid_mockup_timestamp(value: object) -> bool:
    if not isinstance(value, str) or not value.strip():
        return False
    try:
        datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        return False
    return True


def _run_git(root: Path, *args: str, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(root), *args],
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def _relative_path(value: object) -> str | None:
    if not isinstance(value, str) or not value.strip() or "\\" in value:
        return None
    text = value.strip()
    path = PurePosixPath(text)
    if path.is_absolute() or ".." in path.parts or text == ".":
        return None
    return text


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _substantive_markdown(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return False
    text = re.sub(r"<!--.*?-->", "", text, flags=re.DOTALL)
    return bool(text.strip())


def consumer_entry_contract(root: Path) -> dict[str, Any]:
    try:
        plan = plan_consumer_entry(root, SCRIPT_DIR.parent / "templates" / "AGENTS.md.tmpl")
    except (ConsumerEntryError, OSError, RuntimeError, ValueError) as exc:
        return {"status": "unknown", "path": "AGENTS.md", "reason": str(exc)}
    return plan.contract()


def _markdown_repo_links(index_path: Path, root: Path) -> set[str]:
    try:
        text = index_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return set()
    try:
        base = index_path.relative_to(root).parent.as_posix()
    except ValueError:
        return set()
    links: set[str] = set()
    for match in re.finditer(r"\[[^\]]*\]\(([^)]+)\)", text):
        target = match.group(1).strip()
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1].strip()
        target = target.split("#", 1)[0].strip()
        if not target or "://" in target or target.startswith(("/", "#")):
            continue
        normalized = posixpath.normpath(posixpath.join(base, target))
        pure = PurePosixPath(normalized)
        if normalized == "docs" or not _is_pure_within(pure, PurePosixPath("docs")):
            continue
        links.add(normalized.rstrip("/"))
    return links


class Audit:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.findings: list[dict[str, Any]] = []
        self._finding_keys: set[tuple[str, str, str]] = set()
        self.tracked: set[str] = set()
        self.modules: list[dict[str, Any]] = []
        self.contract_targets: list[dict[str, Any]] = []
        self.project_definition: dict[str, Any] = {
            "state": "absent",
            "type": None,
            "root": None,
            "entrypoints": [],
        }
        self.mockups: dict[str, Any] = {"state": "absent", "variants": 0}
        self.proposal: dict[str, Any] = {"state": "equivalent_baseline"}
        self.consumer_contract: dict[str, Any] = {
            "state": "unversioned",
            "schema_version": None,
            "layout_version": None,
            "archive": None,
            "modules": {},
        }
        self.entry_contract = consumer_entry_contract(root)

    def add(
        self,
        level: str,
        code: str,
        message: str,
        path: str | None = None,
        *,
        kind: str | None = None,
        blocking: bool | None = None,
        repair_action: dict[str, Any] | None = None,
    ) -> None:
        if kind is None:
            kind = {
                "error": FINDING_INVALID,
                "sync": FINDING_FRAMEWORK_SYNC,
                "warning": FINDING_ADVISORY,
            }.get(level, FINDING_ADVISORY)
        if blocking is None:
            blocking = level == "error"
        item: dict[str, Any] = {
            "level": level,
            "code": code,
            "kind": kind,
            "blocking": blocking,
            "message": message,
        }
        if path:
            item["path"] = path
        if repair_action is not None:
            item["repair_action"] = repair_action
        key = (level, code, path or "")
        if key in self._finding_keys:
            return
        self._finding_keys.add(key)
        self.findings.append(item)

    def _managed_path(self, relative: str, *, kind: str, level: str = "error") -> Path | None:
        path = self.root / relative
        if not os.path.lexists(path):
            code = "missing_required_file" if kind == "文件" else "missing_required_directory"
            self.add(level, code, f"缺少当前规范要求的{kind}：{relative}", relative)
            return None
        if path.is_symlink():
            self.add("error", "managed_path_symlink", f"框架管理路径不能是 symlink：{relative}", relative)
            return None
        expected = path.is_file() if kind == "文件" else path.is_dir()
        if not expected:
            self.add("error", "managed_path_type", f"框架管理路径类型不正确：{relative}", relative)
            return None
        if not os.access(path, os.R_OK):
            self.add("error", "managed_path_unreadable", f"框架管理路径不可读：{relative}", relative)
            return None
        return path

    def _load_config(self, config: Path) -> None:
        try:
            parsed = parse_yaml_subset(config.read_text(encoding="utf-8"))
            builder = parsed.get("builder")
            if not isinstance(builder, dict) or not isinstance(builder.get("profiles"), dict):
                raise ValueError("builder.profiles 缺失")
            consumer = parsed.get("consumer")
            if consumer is None:
                self.add(
                    "sync",
                    "consumer_layout_unversioned",
                    "消费仓尚未声明当前布局版本；可在确认旧模块关系后只更新 .pm-workflow/config.yml",
                    ".pm-workflow/config.yml",
                    kind=FINDING_COMPATIBILITY,
                )
                return
            if not isinstance(consumer, dict):
                raise ValueError("consumer 必须是 mapping")
            unknown_consumer = sorted(set(consumer) - {"schema_version", "layout_version", "paths", "compatibility"})
            if unknown_consumer:
                raise ValueError("consumer 含未知字段：" + "、".join(unknown_consumer))
            if consumer.get("schema_version") != 1:
                raise ValueError("consumer.schema_version 必须是 1")
            if consumer.get("layout_version") != CURRENT_LAYOUT_VERSION:
                raise ValueError(f"consumer.layout_version 必须是 {CURRENT_LAYOUT_VERSION}")

            paths = consumer.get("paths", {})
            if not isinstance(paths, dict) or sorted(set(paths) - {"archive"}):
                raise ValueError("consumer.paths 只允许声明 archive")
            archive = paths.get("archive", DEFAULT_ARCHIVE_DIR)
            archive = _relative_path(archive)
            if archive is None or not _is_pure_within(PurePosixPath(archive), PurePosixPath("docs")):
                raise ValueError("consumer.paths.archive 必须是 docs/ 下的仓库相对路径")

            compatibility = consumer.get("compatibility", {})
            if not isinstance(compatibility, dict):
                raise ValueError("consumer.compatibility 必须是 mapping")
            modules: dict[str, dict[str, Any]] = {}
            for entry_id, declaration in compatibility.items():
                if not re.fullmatch(r"module_[A-Za-z0-9_-]+", entry_id):
                    raise ValueError(f"consumer.compatibility 条目名不合法：{entry_id}")
                if not isinstance(declaration, dict):
                    raise ValueError(f"consumer.compatibility.{entry_id} 必须是 mapping")
                unknown = sorted(set(declaration) - {"path", "state", "format", "truth_sources"})
                if unknown:
                    raise ValueError(f"consumer.compatibility.{entry_id} 含未知字段：{'、'.join(unknown)}")
                module_path = _relative_path(declaration.get("path"))
                if module_path is None or len(PurePosixPath(module_path).parts) != 3 \
                    or PurePosixPath(module_path).parts[:2] != ("docs", "modules"):
                    raise ValueError(f"consumer.compatibility.{entry_id}.path 必须指向 docs/modules/<模块>")
                if module_path in modules:
                    raise ValueError(f"consumer.compatibility 重复声明模块：{module_path}")
                state = declaration.get("state")
                if state not in VALID_MODULE_STATES:
                    raise ValueError(f"consumer.compatibility.{entry_id}.state 不合法")
                format_name = declaration.get("format")
                truth_sources = declaration.get("truth_sources", [])
                if not isinstance(truth_sources, list) or any(_relative_path(item) is None for item in truth_sources):
                    raise ValueError(f"consumer.compatibility.{entry_id}.truth_sources 必须是安全路径列表")
                if state == "legacy":
                    if format_name not in VALID_LEGACY_FORMATS or truth_sources:
                        raise ValueError(f"consumer.compatibility.{entry_id} 的 legacy 声明不完整")
                elif state in {"retired", "split"}:
                    if format_name is not None or not truth_sources:
                        raise ValueError(f"consumer.compatibility.{entry_id} 必须声明 truth_sources")
                elif format_name is not None or truth_sources:
                    raise ValueError(f"consumer.compatibility.{entry_id} 的 current 声明不能带兼容字段")
                modules[module_path] = {
                    "id": entry_id,
                    "state": state,
                    "format": format_name,
                    "truth_sources": truth_sources,
                }
            self.consumer_contract = {
                "state": "current",
                "schema_version": 1,
                "layout_version": CURRENT_LAYOUT_VERSION,
                "archive": archive,
                "modules": modules,
            }
        except (OSError, UnicodeError, ProjectDefinitionError, ValueError) as exc:
            self.consumer_contract["state"] = "invalid"
            self.add(
                "error",
                "config_invalid",
                f".pm-workflow/config.yml 无法按当前配置合同读取：{exc}",
                ".pm-workflow/config.yml",
            )

    def check_git_identity(self) -> bool:
        result = _run_git(self.root, "rev-parse", "--show-toplevel")
        if result.returncode != 0:
            self.add("error", "not_git_repository", "当前 PMAI 项目不在可识别的 Git 仓库中")
            return False
        try:
            git_root = Path(result.stdout.strip()).resolve(strict=True)
        except (OSError, RuntimeError):
            self.add("error", "git_root_unreadable", "Git 仓库根目录无法安全解析")
            return False
        if git_root != self.root:
            self.add("error", "wrong_repository_root", "消费仓检查目标不是当前 Git 工作树根目录")
            return False
        tracked = _run_git(self.root, "ls-files", "-z")
        if tracked.returncode != 0:
            self.add("error", "git_index_unreadable", "无法读取 Git 跟踪文件清单")
            return False
        self.tracked = {item for item in tracked.stdout.split("\0") if item}
        return True

    def check_skeleton(self) -> None:
        for relative in PROJECT_REQUIRED_FILES:
            path = self._managed_path(relative, kind="文件")
            if path is None:
                continue
            if relative not in self.tracked:
                self.add(
                    "error",
                    "required_file_untracked",
                    f"必需文件未被 Git 跟踪，换机器后会丢失：{relative}",
                    relative,
                )
        for relative in FRAMEWORK_MANAGED_FILES:
            path = self._managed_path(relative, kind="文件", level="sync")
            if path is None:
                continue
            if relative not in self.tracked:
                self.add(
                    "sync",
                    "framework_file_untracked",
                    f"框架托管文件未被 Git 跟踪，需要刷新：{relative}",
                    relative,
                )
        for relative in PROJECT_REQUIRED_DIRS:
            self._managed_path(relative, kind="目录")
        for relative in FRAMEWORK_MANAGED_DIRS:
            self._managed_path(relative, kind="目录", level="sync")

        config = self.root / ".pm-workflow/config.yml"
        if config.is_file() and not config.is_symlink():
            self._load_config(config)
        if self.consumer_contract["state"] == "current":
            self._managed_path(str(self.consumer_contract["archive"]), kind="目录", level="sync")

        for relative in ("AGENTS.md", "CLAUDE.md"):
            path = self.root / relative
            if not path.is_file() or path.is_symlink():
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                continue
            if "PMAI" not in text or "pmai-" not in text:
                self.add(
                    "sync",
                    "host_rules_missing",
                    f"{relative} 缺少 PMAI 宿主入口规则",
                    relative,
                )
            if "{{PROJECT_NAME}}" in text or "{{PROJECT_BACKGROUND}}" in text:
                self.add(
                    "error",
                    "template_placeholder",
                    f"{relative} 仍残留初始化模板占位符",
                    relative,
                )

        if self.entry_contract["status"] == "stale":
            self.add(
                "sync",
                "host_rules_stale",
                "当前项目的 PMAI 启动规则是旧版本，需要更新",
                "AGENTS.md",
                repair_action={
                    "id": "sync_consumer_entry",
                    "target": "AGENTS.md",
                    "availability": "automatic",
                    "confirmation_required": True,
                },
            )
        elif self.entry_contract["status"] == "unsafe":
            self.add(
                "sync",
                "host_rules_manual_review",
                "当前项目的 PMAI 启动规则无法安全自动更新，需要人工确认",
                "AGENTS.md",
            )

        for relative in HOST_PATHS:
            path = self.root / relative
            if not os.path.lexists(path):
                self.add(
                    "sync",
                    "host_surface_missing",
                    f"项目宿主入口缺失，需要按当前框架刷新：{relative}",
                    relative,
                )
            elif relative not in self.tracked:
                self.add(
                    "sync",
                    "host_surface_untracked",
                    f"项目宿主入口未被 Git 跟踪，换机器后会丢失：{relative}",
                    relative,
                )
        for relative in LEGACY_HOST_PATHS:
            if os.path.lexists(self.root / relative):
                self.add(
                    "warning",
                    "legacy_host_surface",
                    f"发现旧 OpenCode 主控入口；当前版本不再使用或刷新：{relative}",
                    relative,
                    kind=FINDING_LEGACY,
                    blocking=False,
                )

    def check_gitignore_and_secrets(self) -> None:
        for probe in IGNORE_PROBES:
            result = _run_git(self.root, "check-ignore", "-q", "--no-index", "--", probe)
            if result.returncode != 0:
                self.add(
                    "sync",
                    "gitignore_rule_missing",
                    f".gitignore 缺少当前 PMAI 运行时规则：{probe}",
                    ".gitignore",
                )

        secret = ".claude/lark-publish.json"
        if secret in self.tracked:
            self.add(
                "error",
                "secret_config_tracked",
                "飞书发布配置可能含凭据，但已被 Git 跟踪；doctor 未读取其内容",
                secret,
            )
        secret_path = self.root / secret
        if os.path.lexists(secret_path) and secret_path.is_symlink():
            self.add(
                "error",
                "secret_config_symlink",
                "飞书发布配置不能使用 symlink；doctor 未读取其内容",
                secret,
            )

    def check_indexes_and_misplaced_docs(self) -> None:
        docs_index = self.root / "docs/INDEX.md"
        registered = set()
        for index_path in (docs_index, self.root / "docs/modules/INDEX.md"):
            if index_path.is_file() and not index_path.is_symlink():
                registered.update(_markdown_repo_links(index_path, self.root))
        if docs_index.is_file() and not docs_index.is_symlink():
            try:
                text = docs_index.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                text = ""
            required_directories = ["modules/", "inputs/"]
            if self.consumer_contract["state"] == "current":
                archive = PurePosixPath(str(self.consumer_contract["archive"]))
                required_directories.extend(("engineering/", "deliverables/", "proposals/", "decisions/", f"{archive.name}/"))
            for directory in required_directories:
                if directory not in text:
                    self.add(
                        "warning",
                        "docs_index_missing_section",
                        f"docs/INDEX.md 没有接回文档分类：{directory}",
                        "docs/INDEX.md",
                    )

        docs_root = self.root / "docs"
        if docs_root.is_dir() and not docs_root.is_symlink():
            allowed = {"INDEX.md", "CODEBASE-AUDIT.md"}
            for entry in sorted(docs_root.iterdir(), key=lambda item: item.name):
                relative = f"docs/{entry.name}"
                if entry.is_file() and entry.suffix.lower() == ".md" \
                    and entry.name not in allowed and relative not in registered:
                    self.add(
                        "warning",
                        "misplaced_docs_markdown",
                        f"docs/ 顶层文档没有归入当前分类目录：docs/{entry.name}",
                        f"docs/{entry.name}",
                    )

        for relative in ("spec.md", "discussion.md", "decisions.md", "task-plan.md"):
            if os.path.lexists(self.root / relative):
                self.add(
                    "warning",
                    "misplaced_root_document",
                    f"根目录存在应归入模块或归档的旧文档：{relative}",
                    relative,
                )

    def _module_index_text(self) -> str:
        path = self.root / "docs/modules/INDEX.md"
        try:
            return path.read_text(encoding="utf-8") if path.is_file() and not path.is_symlink() else ""
        except (OSError, UnicodeError):
            return ""

    def _read_meta(self, path: Path, relative: str) -> dict[str, Any] | None:
        if path.is_symlink():
            self.add("error", "work_meta_symlink", ".work-meta.json 不能是 symlink", relative)
            return None
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            self.add("error", "work_meta_invalid_json", f"模块状态文件不是合法 JSON：{exc}", relative)
            return None
        if not isinstance(value, dict):
            self.add("error", "work_meta_invalid_type", "模块状态文件顶层必须是 JSON object", relative)
            return None
        return value

    def _check_meta_shape(self, meta: dict[str, Any], relative: str) -> str | None:
        status = meta.get("status")
        if status != "active":
            self.add(
                "warning",
                "legacy_work_status",
                f"当前模型只保留 active .work-meta.json；发现旧状态：{status!r}",
                relative,
            )
        build = meta.get("build")
        try:
            contract = normalize_work_contract(meta)
        except WorkContractError as exc:
            self.add(
                "error",
                "work_contract_invalid",
                f"模块工作合同不合法：{exc}",
                relative,
            )
            return None
        lifecycle = contract.lifecycle_state
        if lifecycle == "ready_to_build":
            if not isinstance(meta.get("design_revision"), int) or meta.get("design_revision", 0) < 1:
                self.add("warning", "ready_design_revision", "模块还没有完整保存已确认的设计版本，暂不能开始制作", relative)
            for key in ("approved_source_hash", "design_checkpoint_commit"):
                if not isinstance(meta.get(key), str) or not meta.get(key, "").strip():
                    self.add("warning", "ready_contract_incomplete", "模块还没有完整保存已确认的设计内容，暂不能开始制作", relative)
            target = meta.get("approved_target")
            paths = target.get("paths") if isinstance(target, dict) else None
            if not isinstance(paths, list) or not paths:
                self.add("warning", "ready_target_missing", "模块还没有确定这次要修改的页面或文件，暂不能开始制作", relative)
            else:
                for value in paths:
                    if _relative_path(value) is None:
                        self.add("warning", "ready_target_invalid", "模块记录的制作范围不正确，暂不能开始制作", relative)
                        break
        if lifecycle in BUILD_STATES:
            if not isinstance(build, dict):
                self.add("error", "build_contract_missing", f"{lifecycle} 状态缺少 build 合同", relative)
                return lifecycle
            version = contract.contract_version
            assert version is not None
            mode = build.get("mode")
            executor = build.get("executor")
            if mode not in VALID_BUILD_MODES:
                self.add("error", "build_mode_invalid", f"build.mode 不合法：{mode!r}", relative)
            if executor is not None and executor not in VALID_EXECUTORS:
                self.add("error", "build_executor_invalid", f"build.executor 不合法：{executor!r}", relative)
            target = build.get("target")
            if not isinstance(target, dict) or target.get("kind") not in {"prototype", "product"}:
                self.add("error", "build_target_invalid", "build.target.kind 缺失或不合法", relative)
            else:
                for key in ("paths", "entrypoints"):
                    values = target.get(key)
                    if not isinstance(values, list) or not values:
                        self.add("error", "build_target_invalid", f"build.target.{key} 必须是非空数组", relative)
                        continue
                    if any(_relative_path(value) is None for value in values):
                        self.add("error", "build_target_invalid", f"build.target.{key} 含不安全路径", relative)
            if version >= 2:
                revision = build.get("design_revision")
                source_hash = build.get("approved_source_hash")
                if not isinstance(revision, int) or isinstance(revision, bool) or revision < 1:
                    self.add("error", "build_design_revision", "build.design_revision 必须是正整数", relative)
                if not isinstance(source_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", source_hash):
                    self.add("error", "build_source_hash", "build.approved_source_hash 必须是 SHA-256", relative)
                acceptance = build.get("acceptance")
                if not isinstance(acceptance, dict):
                    self.add("error", "build_acceptance_invalid", "build.acceptance 必须是 object", relative)
                elif not isinstance(acceptance.get("evidence"), list):
                    self.add("error", "build_acceptance_invalid", "acceptance.evidence 必须是数组", relative)
                if build.get("docs_status") not in VALID_DOCS_STATUSES:
                    self.add("error", "build_docs_status", "build.docs_status 不符合当前合同", relative)
            if version >= 3:
                if not isinstance(build.get("delivery_policy"), dict) or not isinstance(
                    build.get("delivery_policy_hash"), str
                ):
                    self.add("error", "build_delivery_policy", "v3+ build 缺少实现深度合同或 hash", relative)
            if version >= 4:
                acceptance = build.get("acceptance")
                if isinstance(acceptance, dict):
                    if not isinstance(acceptance.get("iteration_evidence"), list):
                        self.add("error", "build_acceptance_v4", "v4+ iteration_evidence 必须是数组", relative)
                if not isinstance(build.get("finalization"), dict):
                    self.add("error", "build_finalization_v4", "v4+ build 缺少 finalization object", relative)
            if lifecycle in {"building", "iterating", "final_check"} and build.get("mode") == "worktree":
                worktree = build.get("worktree") or meta.get("worktree")
                worktree_path = None
                if isinstance(worktree, str) and worktree.strip():
                    worktree_path = Path(worktree).expanduser()
                    if not worktree_path.is_absolute():
                        worktree_path = self.root / worktree_path
                if worktree_path is None or not worktree_path.is_dir():
                    self.add("error", "active_worktree_missing", "active build 声明的 worktree 不存在", relative)
                if not isinstance(build.get("branch"), str) or not build.get("branch", "").strip():
                    self.add("error", "active_branch_missing", "worktree build 缺少可恢复 branch", relative)
            if lifecycle == "final_check":
                audit_dir = build.get("audit_dir")
                if isinstance(audit_dir, str) and audit_dir.strip():
                    audit_path = Path(audit_dir).expanduser()
                    if not audit_path.is_absolute():
                        audit_path = self.root / audit_path
                    if not audit_path.is_dir():
                        self.add("error", "audit_directory_missing", "final_check 声明的验收目录不存在", relative)
        elif isinstance(build, dict):
            self.add("error", "unexpected_build_contract", f"{lifecycle} 状态不应携带 active build 合同", relative)
        return lifecycle

    def check_modules(self) -> list[str]:
        modules_root = self.root / "docs/modules"
        if not modules_root.is_dir() or modules_root.is_symlink():
            return []
        index_text = self._module_index_text()
        active_builds: list[str] = []
        states: list[str] = []
        for entry in sorted(modules_root.iterdir(), key=lambda item: item.name):
            relative_dir = f"docs/modules/{entry.name}"
            if entry.is_symlink():
                self.add("error", "module_symlink", f"模块目录不能是 symlink：{relative_dir}", relative_dir)
                continue
            if entry.is_file():
                if entry.name != "INDEX.md" and entry.suffix.lower() != ".md":
                    self.add("warning", "modules_unknown_file", f"模块目录顶层存在未归类文件：{relative_dir}", relative_dir)
                    continue
                if entry.name != "INDEX.md" and entry.name not in index_text:
                    self.add("warning", "module_index_missing_document", f"功能型规格未登记到模块索引：{entry.name}", "docs/modules/INDEX.md")
                if entry.name != "INDEX.md" and relative_dir not in self.tracked:
                    self.add("warning", "module_document_untracked", f"功能型规格未被 Git 跟踪：{relative_dir}", relative_dir)
                continue
            if not entry.is_dir() or entry.name.startswith("."):
                continue

            existing: set[str] = set()
            present: set[str] = set()
            for name in TRIO:
                document = entry / name
                relative = f"{relative_dir}/{name}"
                if not os.path.lexists(document):
                    continue
                existing.add(name)
                if document.is_symlink():
                    self.add("error", "module_document_symlink", f"模块文档不能是 symlink：{relative}", relative)
                elif not document.is_file():
                    self.add("error", "module_document_type", f"模块文档不是普通文件：{relative}", relative)
                elif not _substantive_markdown(document):
                    self.add("error", "module_document_blank", f"模块文档为空白占位，不能作为有效内容：{relative}", relative)
                else:
                    present.add(name)
            meta_path = entry / ".work-meta.json"
            meta: dict[str, Any] | None = None
            lifecycle: str | None = None
            has_meta = os.path.lexists(meta_path)
            if has_meta:
                meta = self._read_meta(meta_path, f"{relative_dir}/.work-meta.json")
                if meta is not None:
                    lifecycle = self._check_meta_shape(meta, f"{relative_dir}/.work-meta.json")
                    if lifecycle:
                        states.append(lifecycle)
                        if lifecycle in {"building", "iterating", "final_check"}:
                            active_builds.append(entry.name)

            declaration = self.consumer_contract["modules"].get(relative_dir)
            module_state = "current"
            module_format: str | None = None
            truth_sources: list[str] = []
            required_documents: set[str] = set()
            if has_meta:
                required_documents = set(TRIO) if lifecycle != "designing" else {"discussion.md", "decisions.md"}
                if declaration and declaration["state"] != "current":
                    self.add(
                        "warning",
                        "active_module_compatibility_ignored",
                        f"active 模块不能降级为 {declaration['state']}，已按当前 lifecycle 校验：{relative_dir}",
                        ".pm-workflow/config.yml",
                    )
            elif self.consumer_contract["state"] == "current":
                if declaration:
                    module_state = declaration["state"]
                    module_format = declaration["format"]
                    truth_sources = list(declaration["truth_sources"])
                if module_state == "current":
                    required_documents = set(TRIO)
                elif module_state == "legacy":
                    required_documents = {"spec.md", "decisions.md"} if module_format == "spec_decisions" else {"spec.md"}
                    self.add(
                        "warning",
                        "legacy_module_compatible",
                        f"模块按已声明的旧格式保留，不要求补造历史文档：{relative_dir}",
                        relative_dir,
                        kind=FINDING_LEGACY,
                    )
                else:
                    for truth_source in truth_sources:
                        target = self.root / truth_source
                        if not os.path.lexists(target):
                            self.add("error", "module_truth_source_missing", f"{module_state} 模块声明的现行真相源不存在：{truth_source}", truth_source)
                        elif target.is_symlink() or not target.is_file():
                            self.add("error", "module_truth_source_invalid", f"{module_state} 模块声明的真相源不是安全普通文件：{truth_source}", truth_source)
                        elif not _substantive_markdown(target):
                            self.add("error", "module_truth_source_blank", f"{module_state} 模块声明的真相源为空白占位：{truth_source}", truth_source)
                        elif truth_source not in self.tracked:
                            self.add("error", "module_truth_source_untracked", f"{module_state} 模块声明的真相源未被 Git 跟踪：{truth_source}", truth_source)
                    self.add(
                        "warning",
                        "legacy_module_redirected",
                        f"模块已声明为 {module_state}，现行真相源由 compatibility 指向：{relative_dir}",
                        relative_dir,
                        kind=FINDING_LEGACY,
                    )
            else:
                if present == set(TRIO):
                    module_state = "unversioned_complete"
                elif {"spec.md", "decisions.md"}.issubset(present):
                    module_state = "legacy"
                    module_format = "spec_decisions"
                    self.add(
                        "sync",
                        "legacy_module_inferred",
                        f"识别到旧 spec + decisions 模块；确认后只需在 config.yml 记录兼容关系：{relative_dir}",
                        relative_dir,
                        kind=FINDING_COMPATIBILITY,
                    )
                elif present == {"spec.md"}:
                    module_state = "legacy"
                    module_format = "merged_spec"
                    self.add(
                        "sync",
                        "legacy_module_inferred",
                        f"识别到合并式 spec 旧模块；确认后只需在 config.yml 记录兼容关系：{relative_dir}",
                        relative_dir,
                        kind=FINDING_COMPATIBILITY,
                    )
                elif present:
                    module_state = "compatibility_unknown"
                    self.add(
                        "sync",
                        "module_compatibility_ambiguous",
                        f"历史模块无法可靠判断为拆分、退役或其它旧格式，需要声明现行真相源：{relative_dir}",
                        relative_dir,
                        kind=FINDING_COMPATIBILITY,
                    )
                elif not existing:
                    self.add("error", "module_content_missing", f"模块目录没有可识别的有效文档：{relative_dir}", relative_dir)

            for name in sorted(required_documents - present):
                if name not in existing:
                    self.add("error", "module_document_missing", f"模块缺少 {name}：{relative_dir}", f"{relative_dir}/{name}")
            for name in present:
                relative = f"{relative_dir}/{name}"
                if relative not in self.tracked:
                    self.add("error", "module_document_untracked", f"模块有效文档未被 Git 跟踪：{relative}", relative)
            if lifecycle and lifecycle != "designing":
                meta_relative = f"{relative_dir}/.work-meta.json"
                if meta_relative not in self.tracked:
                    self.add("error", "work_meta_untracked", f"可恢复模块状态未被 Git 跟踪：{meta_relative}", meta_relative)
            if entry.name not in index_text:
                self.add("warning", "module_index_missing_module", f"模块未登记到模块索引：{entry.name}", "docs/modules/INDEX.md")
            if meta is not None:
                build = meta.get("build")
                target = build.get("target") if isinstance(build, dict) else meta.get("approved_target")
                if isinstance(target, dict):
                    self.contract_targets.append(
                        {
                            "module": entry.name,
                            "lifecycle_state": lifecycle,
                            "kind": target.get("kind"),
                            "paths": target.get("paths"),
                            "entrypoints": target.get("entrypoints"),
                        }
                    )
            self.modules.append(
                {
                    "name": entry.name,
                    "state": module_state,
                    "format": module_format,
                    "truth_sources": truth_sources,
                    "lifecycle_state": lifecycle,
                    "documents": sorted(present),
                }
            )

        if len(active_builds) > 1:
            self.add(
                "error",
                "multiple_active_builds",
                "存在多个 active build，无法给出唯一恢复入口：" + "、".join(active_builds),
                "docs/modules",
            )
        return states

    def check_project_definition(self, states: list[str]) -> None:
        path = self.root / ".pm-workflow/project.yml"
        required = any(LIFECYCLE_ORDER.get(state, 0) >= LIFECYCLE_ORDER["ready_to_build"] for state in states)
        if not os.path.lexists(path):
            if required:
                self.add("error", "project_definition_missing", "当前阶段必须存在 .pm-workflow/project.yml", ".pm-workflow/project.yml")
            return
        if path.is_symlink():
            self.add("error", "project_definition_symlink", "project.yml 不能是 symlink", ".pm-workflow/project.yml")
            return
        try:
            definition = load_project_definition(path)
        except (ProjectDefinitionError, OSError, UnicodeError) as exc:
            self.project_definition["state"] = "invalid"
            self.add("error", "project_definition_invalid", f"project.yml 不符合当前 schema：{exc}", ".pm-workflow/project.yml")
            return

        self.project_definition = {
            "state": "current",
            "type": definition["project"]["type"],
            "root": definition["implementation"]["root"],
            "entrypoints": list(definition["implementation"]["entrypoints"]),
        }
        project_type = definition["project"]["type"]
        project_entrypoints = list(definition["implementation"]["entrypoints"])
        if ".pm-workflow/project.yml" not in self.tracked:
            self.add("error", "project_definition_untracked", "project.yml 未被 Git 跟踪，换机器后无法继续 build", ".pm-workflow/project.yml")

        source_relative = definition["definition"]["source"]
        source = self.root / source_relative
        if not source.is_file() or source.is_symlink():
            self.add("error", "project_source_missing", f"project.yml 的定稿来源不存在或不是普通文件：{source_relative}", source_relative)

        root_relative = definition["implementation"]["root"]
        implementation_root = self.root if root_relative == "." else self.root / root_relative
        implementation_required = not states or any(
            LIFECYCLE_ORDER.get(state, 0) >= LIFECYCLE_ORDER["building"] for state in states
        )
        try:
            resolved_root = implementation_root.resolve(strict=True)
        except (OSError, RuntimeError):
            resolved_root = None
        if implementation_root.is_symlink() or not implementation_root.is_dir() or resolved_root is None or not _is_within(resolved_root, self.root):
            level = "error" if implementation_required else "warning"
            self.add(level, "implementation_root_invalid", f"声明的实现根不存在、越出仓库或为 symlink：{root_relative}", root_relative)
            return

        root_posix = PurePosixPath("" if root_relative == "." else root_relative)
        for entry_relative in definition["implementation"]["entrypoints"]:
            entry_posix = PurePosixPath(entry_relative)
            try:
                entry_posix.relative_to(root_posix)
            except ValueError:
                self.add("error", "entrypoint_outside_root", f"实现入口不在 implementation.root 内：{entry_relative}", entry_relative)
                continue
            entry = self.root / entry_relative
            try:
                resolved_entry = entry.resolve(strict=True)
            except (OSError, RuntimeError):
                resolved_entry = None
            if entry.is_symlink() or resolved_entry is None or not _is_within(resolved_entry, resolved_root):
                level = "error" if implementation_required else "warning"
                self.add(level, "entrypoint_invalid", f"实现入口不存在、越出实现根或为 symlink：{entry_relative}", entry_relative)

        for contract in self.contract_targets:
            module = contract["module"]
            kind = contract.get("kind")
            if kind is not None and kind != project_type:
                self.add(
                    "error",
                    "build_project_type_mismatch",
                    f"模块 {module} 的 build 类型与 project.yml 不一致",
                    f"docs/modules/{module}/.work-meta.json",
                )
            entries = contract.get("entrypoints")
            if isinstance(entries, list) and entries and entries != project_entrypoints:
                self.add(
                    "error",
                    "build_entrypoints_mismatch",
                    f"模块 {module} 的 build entrypoints 与 project.yml 不一致",
                    f"docs/modules/{module}/.work-meta.json",
                )
            paths = contract.get("paths")
            if not isinstance(paths, list):
                continue
            for target_path in paths:
                normalized = _relative_path(target_path)
                if normalized is None:
                    continue
                target_posix = PurePosixPath(normalized)
                if root_relative != "." and not _is_pure_within(target_posix, root_posix):
                    self.add(
                        "error",
                        "build_target_outside_root",
                        f"模块 {module} 的批准路径超出 implementation.root：{normalized}",
                        f"docs/modules/{module}/.work-meta.json",
                    )
                    continue
                if not any(
                    _is_pure_within(target_posix, PurePosixPath(entrypoint))
                    for entrypoint in project_entrypoints
                ):
                    self.add(
                        "error",
                        "build_target_outside_entrypoints",
                        f"模块 {module} 的批准路径没有命中 project.yml entrypoints：{normalized}",
                        f"docs/modules/{module}/.work-meta.json",
                    )

        declared_root = PurePosixPath("." if root_relative == "." else root_relative)
        for conventional in ("prototype", "prototypes"):
            candidate = self.root / conventional
            if not candidate.is_dir() or candidate.is_symlink():
                continue
            candidate_path = PurePosixPath(conventional)
            if root_relative == "." or _is_pure_within(candidate_path, declared_root) or _is_pure_within(declared_root, candidate_path):
                continue
            self.add(
                "warning",
                "orphan_prototype_directory",
                f"发现未被 project.yml 实现根覆盖的原型目录：{conventional}/",
                conventional,
            )

    def check_proposal(self) -> None:
        state = proposal_state(self.root)
        name = str(state.get("state") or "invalid")
        if name == "accepted":
            current = state.get("proposal")
            if not isinstance(current, dict):
                self.proposal = {"state": "invalid"}
                self.add(
                    "error",
                    "proposal_contract_invalid",
                    "当前 Product Proposal 合同缺少可读取版本。",
                    ".pm-workflow/proposal.json",
                )
                return
            path = str(current["path"])
            self.proposal = {
                "state": "accepted",
                "id": current["id"],
                "path": path,
                "supersedes": current["supersedes"],
            }
            for relative in (".pm-workflow/proposal.json", path):
                if relative not in self.tracked:
                    self.add(
                        "error",
                        "proposal_source_untracked",
                        f"当前 Product Proposal 依据未被 Git 跟踪：{relative}",
                        relative,
                    )
            return
        self.proposal = {"state": name}
        if name == "required":
            self.proposal["reason"] = str(state.get("reason") or "product_direction_required")
            self.proposal["gaps"] = [str(item) for item in state.get("gaps") or []]
        if name == "invalid":
            self.proposal["reason"] = str(state.get("reason") or "未知错误")
            self.add(
                "error",
                "proposal_contract_invalid",
                "当前 Product Proposal 与产品基线不一致：" + self.proposal["reason"],
                ".pm-workflow/proposal.json",
            )

    def check_mockups(self) -> None:
        mockups = self.root / "mockups"
        if not os.path.lexists(mockups):
            return
        if mockups.is_symlink() or not mockups.is_dir():
            self.mockups["state"] = "invalid"
            self.add("error", "mockups_directory_invalid", "mockups/ 必须是仓内普通目录", "mockups")
            return
        manifest = mockups / "manifest.json"
        if not manifest.is_file() or manifest.is_symlink():
            self.mockups["state"] = "invalid"
            self.add("error", "mockups_manifest_missing", "存在 mockups/ 时必须有 manifest.json", "mockups/manifest.json")
            return
        if "mockups/manifest.json" not in self.tracked:
            self.add("warning", "mockups_manifest_untracked", "mockups manifest 未被 Git 跟踪", "mockups/manifest.json")
        try:
            data = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            self.mockups["state"] = "invalid"
            self.add("error", "mockups_manifest_invalid", f"mockups manifest 不是合法 JSON：{exc}", "mockups/manifest.json")
            return
        if not isinstance(data, dict) or not isinstance(data.get("variants"), list):
            self.mockups["state"] = "invalid"
            self.add("error", "mockups_variants_invalid", "mockups manifest 的 variants 必须是数组", "mockups/manifest.json")
            return

        self.mockups = {"state": "current", "variants": len(data["variants"])}
        seen: set[str] = set()
        quality_pairs: dict[tuple[str, str], set[str]] = {}
        for index, variant in enumerate(data["variants"]):
            label = f"mockups/manifest.json#variants[{index}]"
            if not isinstance(variant, dict):
                self.add("error", "mockup_variant_invalid", f"第 {index + 1} 个 mockup 变体必须是 object", "mockups/manifest.json")
                continue
            invalid_fields = [
                key
                for key, expected in MOCKUP_REQUIRED_KEYS.items()
                if not isinstance(variant.get(key), expected)
                or (expected is str and not str(variant.get(key)).strip())
            ]
            if invalid_fields:
                self.add("error", "mockup_variant_fields", f"{label} 缺少或写错字段：{', '.join(invalid_fields)}", "mockups/manifest.json")
            uses_current_schema = any(key in variant for key in MOCKUP_CURRENT_KEYS)
            if uses_current_schema:
                invalid_current_fields = [
                    key
                    for key, expected in MOCKUP_CURRENT_KEYS.items()
                    if not isinstance(variant.get(key), expected)
                    or not str(variant.get(key)).strip()
                ]
                if invalid_current_fields:
                    self.add(
                        "error",
                        "mockup_variant_current_fields",
                        f"{label} 使用新版看版字段时必须补齐：{', '.join(invalid_current_fields)}",
                        "mockups/manifest.json",
                    )
                elif not _valid_mockup_timestamp(variant.get("created_at")) \
                        or not _valid_mockup_timestamp(variant.get("updated_at")):
                    self.add(
                        "error",
                        "mockup_variant_timestamp",
                        f"{label} 的 created_at / updated_at 必须是带日期时间的 ISO 8601",
                        "mockups/manifest.json",
                    )
            quality_schema = variant.get("schema_version")
            quality_binding: tuple[str, str] | None = None
            if quality_schema is not None and quality_schema != MOCKUP_QUALITY_SCHEMA_VERSION:
                self.add(
                    "error",
                    "mockup_variant_schema_version",
                    f"{label} 的 schema_version 不受支持",
                    "mockups/manifest.json",
                )
            if quality_schema == MOCKUP_QUALITY_SCHEMA_VERSION:
                invalid_current_fields = [
                    key
                    for key, expected in MOCKUP_CURRENT_KEYS.items()
                    if not isinstance(variant.get(key), expected)
                    or not str(variant.get(key)).strip()
                ]
                if invalid_current_fields:
                    self.add(
                        "error",
                        "mockup_variant_current_fields",
                        f"{label} 的新版比较字段缺少：{', '.join(invalid_current_fields)}",
                        "mockups/manifest.json",
                    )
                invalid_quality_fields = [
                    key
                    for key, expected in MOCKUP_QUALITY_KEYS.items()
                    if not isinstance(variant.get(key), expected)
                    or not str(variant.get(key)).strip()
                ]
                if invalid_quality_fields:
                    self.add(
                        "error",
                        "mockup_quality_fields",
                        f"{label} 的新版质量证据缺少：{', '.join(invalid_quality_fields)}",
                        "mockups/manifest.json",
                    )
                else:
                    basis = _relative_path(variant.get("design_basis"))
                    audit = _relative_path(variant.get("visual_audit"))
                    if basis is None or audit is None \
                            or not basis.startswith("audits/") \
                            or not audit.startswith("audits/"):
                        self.add(
                            "error",
                            "mockup_quality_paths",
                            f"{label} 的 design_basis / visual_audit 必须是 mockups/audits/ 内的相对路径",
                            "mockups/manifest.json",
                        )
                    else:
                        quality_binding = (basis, audit)
            if variant.get("status") not in MOCKUP_STATUSES:
                self.add("error", "mockup_variant_status", f"{label} 的 status 不符合当前枚举", "mockups/manifest.json")
            relative = _relative_path(variant.get("path"))
            if relative is None:
                self.add("error", "mockup_variant_path", f"{label} 的 path 不是安全的 mockups 相对路径", "mockups/manifest.json")
                continue
            if relative in seen:
                self.add("error", "mockup_variant_duplicate", f"mockup 变体路径重复：{relative}", "mockups/manifest.json")
                continue
            seen.add(relative)
            if quality_binding is not None:
                quality_pairs.setdefault(quality_binding, set()).add(f"mockups/{relative}")
            asset = mockups / relative
            try:
                resolved = asset.resolve(strict=True)
            except (OSError, RuntimeError):
                resolved = None
            if asset.is_symlink() or not asset.is_file() or resolved is None or not _is_within(resolved, mockups):
                self.add("error", "mockup_asset_missing", f"mockup 资源不存在、越界或为 symlink：{relative}", f"mockups/{relative}")
            elif f"mockups/{relative}" not in self.tracked:
                self.add("warning", "mockup_asset_untracked", f"mockup 资源未被 Git 跟踪：{relative}", f"mockups/{relative}")

        quality_checker = SCRIPT_DIR / "mockup-quality.py"
        for (basis, audit), variants in sorted(quality_pairs.items()):
            if not quality_checker.is_file():
                self.add("error", "mockup_quality_checker_missing", "无法验证 mockup 设计质量证据")
                break
            command = [
                    sys.executable,
                    str(quality_checker),
                    "verify",
                    "--repo",
                    str(self.root),
                    "--contract",
                    f"mockups/{basis}",
                    "--report",
                    f"mockups/{audit}",
                ]
            for variant in sorted(variants):
                command.extend(["--variant", variant])
            result = subprocess.run(
                command,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
                check=False,
            )
            if result.returncode != 0:
                reason = (result.stderr or "").strip().removeprefix("MOCKUP_QUALITY: FAIL: ")
                self.add(
                    "error",
                    "mockup_quality_invalid",
                    f"mockup 设计质量证据无效：{reason or '请重新执行视觉验收'}",
                    f"mockups/{audit}",
                )

        if data["variants"]:
            board = mockups / "index.html"
            viewer = mockups / "viewer.html"
            if not board.is_file() or not viewer.is_file():
                self.add("warning", "mockup_board_missing", "mockups 看版尚未从 manifest 完整生成", "mockups/index.html")
            else:
                for generated in ("mockups/index.html", "mockups/viewer.html"):
                    if generated not in self.tracked:
                        self.add("warning", "mockup_board_untracked", f"生成看板未被 Git 跟踪：{generated}", generated)
                self._check_mockup_board_freshness(manifest, board, viewer)

    def _check_mockup_board_freshness(self, manifest: Path, board: Path, viewer: Path) -> None:
        generator = SCRIPT_DIR / "gen-mock-board.py"
        if not generator.is_file():
            self.add("warning", "mockup_generator_missing", "无法验证 mockups 看版是否与 manifest 一致")
            return
        with tempfile.TemporaryDirectory(prefix="pmai-doctor-mockups-") as tmp:
            out = Path(tmp) / "index.html"
            result = subprocess.run(
                [sys.executable, str(generator), str(self.root), "--manifest", str(manifest), "--out", str(out)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            generated_viewer = out.parent / "viewer.html"
            if result.returncode != 0 or not out.is_file() or not generated_viewer.is_file():
                self.add("warning", "mockup_board_unverifiable", "无法只读重建 mockups 看版进行比较")
                return
            if board.read_bytes() != out.read_bytes() or viewer.read_bytes() != generated_viewer.read_bytes():
                self.add("warning", "mockup_board_stale", "mockups 看版落后于 manifest，需要重新生成", "mockups/index.html")

    def check_legacy_layout(self) -> None:
        legacy_paths = (
            "requirements/active",
            "requirements/closed",
            "tasks",
            ".framework-sync-state.json",
            ".claude/scripts/status-view.py",
            ".claude/scripts/init-project.sh",
        )
        for relative in legacy_paths:
            if os.path.lexists(self.root / relative):
                self.add("sync", "legacy_layout", f"发现当前版本不再使用的旧结构：{relative}", relative)
        for base in (".claude/skills", ".codex/skills"):
            directory = self.root / base
            if not directory.is_dir() or directory.is_symlink():
                continue
            if any(item.name.startswith("pmai-") for item in directory.iterdir()):
                self.add("sync", "legacy_local_skills", f"发现项目级 PMAI skill 副本：{base}/pmai-*", base)

    def phase(self, states: list[str]) -> str:
        if states:
            return max(states, key=lambda state: LIFECYCLE_ORDER.get(state, 0))
        if self.project_definition["state"] != "absent":
            return "defined"
        return "initialized"

    def payload(self, states: list[str]) -> dict[str, Any]:
        counts = {level: sum(1 for item in self.findings if item["level"] == level) for level in ("error", "sync", "warning")}
        kinds = {
            kind: sum(1 for item in self.findings if item["kind"] == kind)
            for kind in (FINDING_FRAMEWORK_SYNC, FINDING_LEGACY, FINDING_COMPATIBILITY, FINDING_INVALID, FINDING_ADVISORY)
        }
        blocking = any(item["blocking"] for item in self.findings)
        sync_required = any(
            item["kind"] in {FINDING_FRAMEWORK_SYNC, FINDING_COMPATIBILITY}
            for item in self.findings
        )
        status = "invalid" if blocking else "sync_required" if sync_required else "current"
        return {
            "schema_version": SCHEMA_VERSION,
            "status": status,
            "phase": self.phase(states),
            "summary": counts,
            "classification_summary": kinds,
            "entry_contract": self.entry_contract,
            "consumer_contract": self.consumer_contract,
            "project_definition": self.project_definition,
            "proposal": self.proposal,
            "mockups": self.mockups,
            "modules": self.modules,
            "findings": self.findings,
        }


def _is_pure_within(path: PurePosixPath, parent: PurePosixPath) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def audit_consumer(root: Path) -> dict[str, Any]:
    audit = Audit(root)
    if audit.check_git_identity():
        audit.check_skeleton()
        audit.check_gitignore_and_secrets()
        audit.check_indexes_and_misplaced_docs()
        audit.check_proposal()
        states = audit.check_modules()
        audit.check_project_definition(states)
        audit.check_mockups()
        audit.check_legacy_layout()
    else:
        states = []
    return audit.payload(states)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--entry-only", action="store_true")
    args = parser.parse_args(argv)
    try:
        root = Path(args.repo_root).expanduser().resolve(strict=True)
        if not root.is_dir():
            raise ValueError("消费仓根目录不是目录")
        if args.entry_only:
            entry = consumer_entry_contract(root)
            print(json.dumps(entry, ensure_ascii=False, indent=2))
            if entry["status"] == "current":
                return 0
            if entry["status"] == "stale":
                return 1
            return 2
        payload = audit_consumer(root)
    except (OSError, RuntimeError, ValueError) as exc:
        print(
            json.dumps(
                {
                    "schema_version": SCHEMA_VERSION,
                    "status": "invalid",
                    "phase": "unknown",
                    "summary": {"error": 1, "sync": 0, "warning": 0},
                    "classification_summary": {
                        FINDING_FRAMEWORK_SYNC: 0,
                        FINDING_LEGACY: 0,
                        FINDING_COMPATIBILITY: 0,
                        FINDING_INVALID: 1,
                        FINDING_ADVISORY: 0,
                    },
                    "entry_contract": {"status": "unknown", "path": "AGENTS.md"},
                    "consumer_contract": {
                        "state": "unknown",
                        "schema_version": None,
                        "layout_version": None,
                        "archive": None,
                        "modules": {},
                    },
                    "project_definition": {
                        "state": "unknown",
                        "type": None,
                        "root": None,
                        "entrypoints": [],
                    },
                    "proposal": {"state": "unknown"},
                    "mockups": {"state": "unknown", "variants": 0},
                    "modules": [],
                    "findings": [
                        {
                            "level": "error",
                            "code": "consumer_audit_unavailable",
                            "kind": FINDING_INVALID,
                            "blocking": True,
                            "message": str(exc),
                        }
                    ],
                },
                ensure_ascii=False,
                indent=2,
            )
        )
        return 2
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
