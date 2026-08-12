"""Adapter boundary from optional review providers to the core Build contract."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def validate_review_approval(
    *,
    provider: str,
    repo_root: Path,
    module_dir: Path,
    reference: str,
    artifact: str | None,
    scripts_dir: Path,
) -> dict[str, object]:
    if provider != "lark-review-batch":
        raise SystemExit(f"不支持的评审证据提供方：{provider}")
    if not artifact:
        raise SystemExit(
            "lark-review-batch accepted delta 必须提供 --approval-artifact "
            "指向本批 remote-verification.json。"
        )
    command = [
        sys.executable,
        str(scripts_dir / "lark-review.py"),
        "validate-approval",
        "--artifact",
        artifact,
        "--repo-root",
        str(repo_root),
        "--markdown",
        str(module_dir.expanduser().resolve() / "spec.md"),
        "--batch-id",
        reference,
    ]
    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"无法运行 Lark 审批证据验证器：{exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.strip()
        if detail.startswith("ERROR: "):
            detail = detail[7:]
        raise SystemExit(f"Lark 审批证据无效：{detail or '完整批次校验失败'}")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit("Lark 审批证据验证器没有返回合法 JSON。") from exc
    if not isinstance(payload, dict) or payload.get("batch_id") != reference:
        raise SystemExit("Lark 审批证据验证器返回了不匹配的批次。")
    return payload
