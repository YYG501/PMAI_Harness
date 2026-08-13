"""Stable browser-acceptance artifact fields shared by producer and validators."""

from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping


LEGACY_BROWSER_CHECK_COVERAGE = {
    "browser-smoke": "smoke",
    "visual": "visual",
    "behavior": "behavior",
}


def browser_batch_digest(artifact: Mapping[str, Any]) -> str:
    payload = {
        key: artifact.get(key)
        for key in (
            "schema_version",
            "check",
            "status",
            "implementation_commit",
            "source_hash",
            "manifest_hash",
            "single_chain_invocation",
            "covers",
            "flows",
            "exit_code",
            "visual_artifacts",
            "missing_visual_artifacts",
        )
    }
    return hashlib.sha256(
        json.dumps(
            payload,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()
