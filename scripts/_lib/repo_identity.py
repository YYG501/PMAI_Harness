"""Single source of truth for PMAI repository identity."""

from __future__ import annotations

from enum import Enum
from pathlib import Path


class RepoIdentityError(RuntimeError):
    """Raised when a repository root cannot be classified safely."""


class RepoKind(str, Enum):
    GENERATOR = "generator"
    CONSUMER = "consumer"
    UNINITIALIZED = "uninitialized"


_GENERATOR_MARKERS = (
    "RUNTIME.md",
    "CLAUDE.md",
    "skills/init-project/SKILL.md",
)

_CONSUMER_STRONG_MARKERS = (
    ".pm-workflow/config.yml",
    ".opencode/commands/pmai-build.md",
    "docs/CONTEXT.md",
)

_LEGACY_CONSUMER_MARKERS = (
    "PRODUCT.md",
    "PRODUCT-STATE.md",
    "docs/PRODUCT.md",
    "docs/PRODUCT-STATE.md",
)

_PMAI_TEXT_MARKERS = (
    "PMAI",
    "/pmai-",
    "$pmai-",
    "/skill:pmai-",
)


def _root(path: Path) -> Path:
    try:
        return path.expanduser().resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise RepoIdentityError(f"repository root is not readable: {path}") from exc


def _safe_file(root: Path, relative: str) -> Path | None:
    candidate = root / relative
    try:
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, RuntimeError, ValueError):
        return None
    return resolved if resolved.is_file() else None


def _has_file(root: Path, relative: str) -> bool:
    return _safe_file(root, relative) is not None


def _mentions_pmai(root: Path, relative: str) -> bool:
    path = _safe_file(root, relative)
    if path is None:
        return False
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return False
    return any(marker in text for marker in _PMAI_TEXT_MARKERS)


def classify_repo(path: Path) -> RepoKind:
    """Classify one checkout root without guessing from generic directories."""

    root = _root(path)
    if not root.is_dir():
        raise RepoIdentityError(f"repository root is not a directory: {path}")

    if all(_has_file(root, marker) for marker in _GENERATOR_MARKERS):
        return RepoKind.GENERATOR

    if any(_has_file(root, marker) for marker in _CONSUMER_STRONG_MARKERS):
        return RepoKind.CONSUMER

    if any(
        _mentions_pmai(root, marker)
        for marker in ("AGENTS.md", "CLAUDE.md", ".codex/hooks.json", "opencode.json")
    ):
        return RepoKind.CONSUMER

    legacy_marker_count = sum(
        _has_file(root, marker) for marker in _LEGACY_CONSUMER_MARKERS
    )
    if legacy_marker_count >= 2:
        return RepoKind.CONSUMER

    return RepoKind.UNINITIALIZED
