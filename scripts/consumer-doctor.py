#!/usr/bin/env python3
"""Read-only PMAI consumer repository topology and lifecycle diagnostics."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _lib.project_definition import (  # noqa: E402
    ProjectDefinitionError,
    load_project_definition,
    parse_yaml_subset,
)


SCHEMA_VERSION = 1
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
REQUIRED_FILES = (
    ".gitignore",
    "AGENTS.md",
    "CLAUDE.md",
    "PRODUCT.md",
    "PRODUCT-STATE.md",
    "DESIGN.md",
    "PRODUCT-RULES.md",
    "TODO.md",
    "docs/INDEX.md",
    "docs/modules/INDEX.md",
    "docs/engineering/INDEX.md",
    "docs/deliverables/INDEX.md",
    "docs/inputs/.gitkeep",
    "docs/archive/.gitkeep",
    "docs/decisions/.gitkeep",
    ".pm-workflow/config.yml",
    "templates/lark-publish.json.tmpl",
)
REQUIRED_DIRS = (
    "docs/modules",
    "docs/inputs",
    "docs/engineering",
    "docs/deliverables",
    "docs/archive",
    "docs/decisions",
    ".pm-workflow",
)
HOST_PATHS = (
    ".claude/settings.json",
    ".codex/hooks.json",
    ".opencode/commands",
    "opencode.json",
)
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


class Audit:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.findings: list[dict[str, str]] = []
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

    def add(self, level: str, code: str, message: str, path: str | None = None) -> None:
        item = {"level": level, "code": code, "message": message}
        if path:
            item["path"] = path
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
        for relative in REQUIRED_FILES:
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
        for relative in REQUIRED_DIRS:
            self._managed_path(relative, kind="目录")

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
                    "error",
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

        config = self.root / ".pm-workflow/config.yml"
        if config.is_file() and not config.is_symlink():
            try:
                parsed = parse_yaml_subset(config.read_text(encoding="utf-8"))
                builder = parsed.get("builder")
                if not isinstance(builder, dict) or not isinstance(builder.get("profiles"), dict):
                    raise ValueError("builder.profiles 缺失")
            except (OSError, UnicodeError, ProjectDefinitionError, ValueError) as exc:
                self.add(
                    "error",
                    "config_invalid",
                    f".pm-workflow/config.yml 无法按当前配置合同读取：{exc}",
                    ".pm-workflow/config.yml",
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
            elif relative != ".opencode/commands" and relative not in self.tracked:
                self.add(
                    "sync",
                    "host_surface_untracked",
                    f"项目宿主入口未被 Git 跟踪，换机器后会丢失：{relative}",
                    relative,
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
        if docs_index.is_file() and not docs_index.is_symlink():
            try:
                text = docs_index.read_text(encoding="utf-8")
            except (OSError, UnicodeError):
                text = ""
            for directory in ("modules/", "inputs/", "engineering/", "deliverables/", "decisions/", "archive/"):
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
                if entry.is_file() and entry.suffix.lower() == ".md" and entry.name not in allowed:
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
        lifecycle = meta.get("lifecycle_state")
        build = meta.get("build")
        if isinstance(build, dict):
            build_lifecycle = build.get("lifecycle_state")
            if lifecycle and build_lifecycle and lifecycle != build_lifecycle:
                self.add(
                    "error",
                    "lifecycle_mismatch",
                    "模块顶层 lifecycle_state 与 build 合同不一致",
                    relative,
                )
            lifecycle = build_lifecycle or lifecycle
        if lifecycle not in LIFECYCLE_ORDER:
            self.add(
                "error",
                "lifecycle_invalid",
                f"模块 lifecycle_state 不合法：{lifecycle!r}",
                relative,
            )
            return None
        if lifecycle == "ready_to_build":
            if not isinstance(meta.get("design_revision"), int) or meta.get("design_revision", 0) < 1:
                self.add("error", "ready_design_revision", "ready_to_build 缺少合法 design_revision", relative)
            for key in ("approved_source_hash", "design_checkpoint_commit"):
                if not isinstance(meta.get(key), str) or not meta.get(key, "").strip():
                    self.add("error", "ready_contract_incomplete", f"ready_to_build 缺少 {key}", relative)
            target = meta.get("approved_target")
            paths = target.get("paths") if isinstance(target, dict) else None
            if not isinstance(paths, list) or not paths:
                self.add("error", "ready_target_missing", "ready_to_build 缺少 approved_target.paths", relative)
            else:
                for value in paths:
                    if _relative_path(value) is None:
                        self.add("error", "ready_target_invalid", "ready_to_build 含不安全的批准目标路径", relative)
                        break
        if lifecycle in BUILD_STATES:
            if not isinstance(build, dict):
                self.add("error", "build_contract_missing", f"{lifecycle} 状态缺少 build 合同", relative)
                return lifecycle
            try:
                version = int(build.get("contract_version", 1))
            except (TypeError, ValueError):
                version = 0
            if version < 1 or version > 4:
                self.add(
                    "error",
                    "build_contract_version",
                    f"build.contract_version 不受当前框架支持：{build.get('contract_version')!r}",
                    relative,
                )
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
                else:
                    required_checks = acceptance.get("required_checks")
                    if not isinstance(required_checks, list) or not required_checks or any(
                        not isinstance(item, str) or not item.strip() for item in required_checks
                    ):
                        self.add("error", "build_acceptance_invalid", "acceptance.required_checks 必须是非空字符串数组", relative)
                    if not isinstance(acceptance.get("evidence"), list):
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
                    iteration_checks = acceptance.get("iteration_checks")
                    final_checks = acceptance.get("final_checks")
                    required_checks = acceptance.get("required_checks")
                    if not isinstance(iteration_checks, list) or not isinstance(final_checks, list):
                        self.add("error", "build_acceptance_v4", "v4 acceptance 缺少 iteration_checks / final_checks", relative)
                    elif not final_checks or final_checks != required_checks:
                        self.add("error", "build_acceptance_v4", "v4 final_checks 必须与 required_checks 一致", relative)
                    if not isinstance(acceptance.get("iteration_evidence"), list):
                        self.add("error", "build_acceptance_v4", "v4 iteration_evidence 必须是数组", relative)
                if not isinstance(build.get("finalization"), dict):
                    self.add("error", "build_finalization_v4", "v4 build 缺少 finalization object", relative)
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
                elif entry.name != "INDEX.md" and entry.name not in index_text:
                    self.add("warning", "module_index_missing_document", f"功能型规格未登记到模块索引：{entry.name}", "docs/modules/INDEX.md")
                if entry.name != "INDEX.md" and relative_dir not in self.tracked:
                    self.add("warning", "module_document_untracked", f"功能型规格未被 Git 跟踪：{relative_dir}", relative_dir)
                continue
            if not entry.is_dir() or entry.name.startswith("."):
                continue

            present = {name for name in TRIO if (entry / name).is_file() and not (entry / name).is_symlink()}
            meta_path = entry / ".work-meta.json"
            meta: dict[str, Any] | None = None
            lifecycle: str | None = None
            if os.path.lexists(meta_path):
                meta = self._read_meta(meta_path, f"{relative_dir}/.work-meta.json")
                if meta is not None:
                    lifecycle = self._check_meta_shape(meta, f"{relative_dir}/.work-meta.json")
                    if lifecycle:
                        states.append(lifecycle)
                        if lifecycle in {"building", "iterating", "final_check"}:
                            active_builds.append(entry.name)

            required_trio = set(TRIO) if lifecycle != "designing" else {"discussion.md", "decisions.md"}
            if meta is None and present:
                required_trio = set(TRIO)
            for name in sorted(required_trio - present):
                level = "warning" if lifecycle == "designing" else "error"
                self.add(level, "module_document_missing", f"模块缺少 {name}：{relative_dir}", f"{relative_dir}/{name}")
            for name in present:
                relative = f"{relative_dir}/{name}"
                if lifecycle != "designing" and relative not in self.tracked:
                    self.add("error", "module_document_untracked", f"已定稿模块文档未被 Git 跟踪：{relative}", relative)
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
            self.modules.append({"name": entry.name, "lifecycle_state": lifecycle, "documents": sorted(present)})

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
            asset = mockups / relative
            try:
                resolved = asset.resolve(strict=True)
            except (OSError, RuntimeError):
                resolved = None
            if asset.is_symlink() or not asset.is_file() or resolved is None or not _is_within(resolved, mockups):
                self.add("error", "mockup_asset_missing", f"mockup 资源不存在、越界或为 symlink：{relative}", f"mockups/{relative}")
            elif f"mockups/{relative}" not in self.tracked:
                self.add("warning", "mockup_asset_untracked", f"mockup 资源未被 Git 跟踪：{relative}", f"mockups/{relative}")

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
        status = "invalid" if counts["error"] else "sync_required" if counts["sync"] else "current"
        return {
            "schema_version": SCHEMA_VERSION,
            "status": status,
            "phase": self.phase(states),
            "summary": counts,
            "project_definition": self.project_definition,
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
    args = parser.parse_args(argv)
    try:
        root = Path(args.repo_root).expanduser().resolve(strict=True)
        if not root.is_dir():
            raise ValueError("消费仓根目录不是目录")
        payload = audit_consumer(root)
    except (OSError, RuntimeError, ValueError) as exc:
        print(json.dumps({"schema_version": SCHEMA_VERSION, "status": "invalid", "phase": "unknown", "summary": {"error": 1, "sync": 0, "warning": 0}, "project_definition": {"state": "unknown", "type": None, "root": None, "entrypoints": []}, "mockups": {"state": "unknown", "variants": 0}, "modules": [], "findings": [{"level": "error", "code": "consumer_audit_unavailable", "message": str(exc)}]}, ensure_ascii=False, indent=2))
        return 2
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
