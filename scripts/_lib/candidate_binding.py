"""Deterministically bind final validation to one approved implementation tree."""

from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Mapping, Sequence


CANDIDATE_BINDING_SCHEMA_VERSION = 1


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def candidate_binding_digest(binding: Mapping[str, Any]) -> str:
    payload = {
        key: value
        for key, value in binding.items()
        if key not in {"bound_at", "binding_digest"}
    }
    return hashlib.sha256(
        json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()


def _git(repo_root: Path, *args: str, binary: bool = False) -> bytes | str:
    result = subprocess.run(
        ["git", "-C", str(repo_root), *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=not binary,
        check=False,
    )
    if result.returncode != 0:
        error = result.stderr if isinstance(result.stderr, str) else result.stderr.decode(
            "utf-8", errors="replace"
        )
        raise ValueError(error.strip() or f"Git 命令失败：{' '.join(args)}")
    return result.stdout


def resolve_commit(repo_root: Path, value: object, label: str) -> str:
    commit = str(value or "").strip()
    if not commit:
        raise ValueError(f"{label} 不能为空。")
    resolved = str(_git(repo_root, "rev-parse", "--verify", f"{commit}^{{commit}}"))
    return resolved.strip()


def commit_exists(repo_root: Path, value: object) -> bool:
    try:
        resolve_commit(repo_root, value, "commit")
    except ValueError:
        return False
    return True


def is_ancestor(repo_root: Path, ancestor: str, descendant: str) -> bool:
    result = subprocess.run(
        ["git", "-C", str(repo_root), "merge-base", "--is-ancestor", ancestor, descendant],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode not in {0, 1}:
        raise ValueError(
            result.stderr.decode("utf-8", errors="replace").strip()
            or "无法验证候选提交承接关系。"
        )
    return result.returncode == 0


def normalize_target_paths(values: object) -> list[str]:
    if not isinstance(values, Sequence) or isinstance(values, (str, bytes)):
        raise ValueError("build.target.paths 必须是非空字符串数组。")
    result: list[str] = []
    for value in values:
        if not isinstance(value, str) or not value.strip():
            raise ValueError("build.target.paths 必须是非空字符串数组。")
        raw = value.strip().replace("\\", "/")
        while raw.startswith("./"):
            raw = raw[2:]
        path = PurePosixPath(raw)
        if path.is_absolute() or raw in {"", ".", ".."} or ".." in path.parts:
            raise ValueError(f"build.target.paths 含不安全路径：{value}")
        normalized = path.as_posix().rstrip("/")
        if normalized not in result:
            result.append(normalized)
    if not result:
        raise ValueError("build.target.paths 不能为空。")
    return sorted(result)


def target_tree(repo_root: Path, commit: str, target_paths: object) -> dict[str, Any]:
    resolved_commit = resolve_commit(repo_root, commit, "候选提交")
    paths = normalize_target_paths(target_paths)
    entries: list[dict[str, str]] = []
    for path in paths:
        try:
            _git(repo_root, "cat-file", "-e", f"{resolved_commit}:{path}")
        except ValueError:
            entries.append(
                {"path": path, "mode": "absent", "type": "absent", "oid": "absent"}
            )
            continue
        output = _git(
            repo_root,
            "ls-tree",
            "-r",
            "-z",
            "--full-tree",
            resolved_commit,
            "--",
            path,
            binary=True,
        )
        assert isinstance(output, bytes)
        path_entries = []
        for raw_entry in output.split(b"\0"):
            if not raw_entry:
                continue
            metadata, separator, raw_name = raw_entry.partition(b"\t")
            fields = metadata.decode("ascii").split()
            if not separator or len(fields) != 3:
                raise ValueError(f"无法解析候选目标树：{path}")
            mode, kind, oid = fields
            path_entries.append(
                {
                    "path": raw_name.decode("utf-8", errors="surrogateescape"),
                    "mode": mode,
                    "type": kind,
                    "oid": oid,
                }
            )
        if not path_entries:
            raise ValueError(f"候选提交 {resolved_commit} 无法解析批准目标：{path}")
        entries.extend(path_entries)
    entries.sort(key=lambda item: (item["path"], item["mode"], item["oid"]))
    payload = {"target_paths": paths, "entries": entries}
    digest = hashlib.sha256(
        json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8", errors="surrogateescape")
    ).hexdigest()
    return {**payload, "digest": digest, "commit": resolved_commit}


def _base_commit(repo_root: Path, build: Mapping[str, Any], source_commit: str) -> str:
    baseline = str(build.get("baseline_sha") or "").strip()
    if baseline and commit_exists(repo_root, baseline):
        return resolve_commit(repo_root, baseline, "baseline_sha")
    parent = subprocess.run(
        ["git", "-C", str(repo_root), "rev-parse", "--verify", f"{source_commit}^"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return parent.stdout.strip() if parent.returncode == 0 else source_commit


def select_candidate(
    repo_root: Path,
    build: Mapping[str, Any],
    recovery: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    target = build.get("target")
    if not isinstance(target, Mapping):
        raise ValueError("build.target 必须是对象。")
    paths = normalize_target_paths(target.get("paths"))
    head = resolve_commit(repo_root, "HEAD", "当前 HEAD")

    if recovery is not None and recovery.get("kind") == "active-build":
        checkpoint = resolve_commit(
            repo_root, recovery.get("checkpoint_commit"), "legacy recovery checkpoint"
        )
        checkpoint_tree = target_tree(repo_root, checkpoint, paths)
        recorded_digest = recovery.get("candidate_target_tree_digest")
        recorded_paths = recovery.get("candidate_target_paths")
        if recorded_digest is not None and (
            recorded_digest != checkpoint_tree["digest"]
            or normalize_target_paths(recorded_paths) != paths
        ):
            raise ValueError("legacy recovery 记录的批准目标树与 checkpoint 不一致。")
        recorded = str(build.get("implementation_commit") or "").strip()
        if recorded and commit_exists(repo_root, recorded):
            recorded = resolve_commit(repo_root, recorded, "implementation_commit")
            recorded_tree = target_tree(repo_root, recorded, paths)
            if (
                recorded != checkpoint
                and is_ancestor(repo_root, checkpoint, recorded)
                and recorded_tree["digest"] != checkpoint_tree["digest"]
            ):
                source_kind = "recorded-implementation"
                source = recorded
            else:
                source_kind = "legacy-recovery-checkpoint"
                source = checkpoint
        else:
            source_kind = "legacy-recovery-checkpoint"
            source = checkpoint
    else:
        recorded = str(build.get("implementation_commit") or "").strip()
        if recorded and commit_exists(repo_root, recorded):
            recorded = resolve_commit(repo_root, recorded, "implementation_commit")
            if target_tree(repo_root, recorded, paths)["digest"] == target_tree(
                repo_root, head, paths
            )["digest"]:
                source_kind = "recorded-implementation"
                source = recorded
            else:
                source_kind = "current-head"
                source = head
        else:
            source_kind = "current-head"
            source = head

    tree = target_tree(repo_root, source, paths)
    binding = {
        "schema_version": CANDIDATE_BINDING_SCHEMA_VERSION,
        "source_kind": source_kind,
        "source_commit": source,
        "base_commit": (
            checkpoint
            if source_kind == "legacy-recovery-checkpoint"
            else (
                checkpoint
                if recovery is not None and recovery.get("kind") == "active-build"
                else _base_commit(repo_root, build, source)
            )
        ),
        "diff_mode": (
            "approved-target-snapshot"
            if source_kind == "legacy-recovery-checkpoint"
            else "commit-range"
        ),
        "target_paths": paths,
        "target_tree_digest": tree["digest"],
        "approved_source_hash": str(build.get("approved_source_hash") or ""),
        "bound_at": now_iso(),
    }
    binding["binding_digest"] = candidate_binding_digest(binding)
    return binding


def validate_candidate_binding(
    repo_root: Path, build: Mapping[str, Any]
) -> dict[str, Any]:
    raw = build.get("candidate_binding")
    if not isinstance(raw, Mapping):
        raise ValueError("build 缺少 candidate_binding；请先绑定正确候选。")
    if raw.get("schema_version") != CANDIDATE_BINDING_SCHEMA_VERSION:
        raise ValueError("build.candidate_binding schema_version 不受支持。")
    if raw.get("binding_digest") != candidate_binding_digest(raw):
        raise ValueError("candidate_binding.binding_digest 不一致，候选绑定可能已被修改。")
    source = resolve_commit(repo_root, raw.get("source_commit"), "candidate source_commit")
    base = resolve_commit(repo_root, raw.get("base_commit"), "candidate base_commit")
    paths = normalize_target_paths(raw.get("target_paths"))
    if raw.get("diff_mode") not in {"commit-range", "approved-target-snapshot"}:
        raise ValueError("candidate_binding.diff_mode 不受支持。")
    target = build.get("target")
    if not isinstance(target, Mapping) or paths != normalize_target_paths(target.get("paths")):
        raise ValueError("candidate_binding 与当前批准目标路径不一致。")
    if source != str(build.get("implementation_commit") or ""):
        raise ValueError("candidate_binding.source_commit 与 implementation_commit 不一致。")
    if raw.get("approved_source_hash") != build.get("approved_source_hash"):
        raise ValueError("candidate_binding 与当前 approved_source_hash 不一致。")
    tree = target_tree(repo_root, source, paths)
    if raw.get("target_tree_digest") != tree["digest"]:
        raise ValueError("candidate_binding 的批准目标树摘要不一致。")
    normalized = dict(raw)
    normalized.update({"source_commit": source, "base_commit": base, "target_paths": paths})
    return normalized
