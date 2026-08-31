#!/usr/bin/env python3
"""Read-only deterministic Judge for a finalize audit binding."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from _lib.finalize_audit import (  # noqa: E402
    binding_digest,
    evidence_digest,
    file_digest,
    git_revision,
    read_object,
    resolve_audit_dir,
    validate_finalize_audit,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binding", required=True)
    parser.add_argument("--consumer-root", required=True)
    args = parser.parse_args()
    binding_path = Path(args.binding).expanduser().resolve()
    binding = read_object(binding_path, "audit binding")
    issues: list[str] = []
    if binding.get("digest") != binding_digest(binding):
        issues.append("audit binding digest 不一致")
    try:
        audit_dir = resolve_audit_dir(Path(args.consumer_root), str(binding.get("audit_dir") or ""))
        audit = validate_finalize_audit(audit_dir)
        files = audit["file_hashes"]
        evidence = binding.get("evidence")
        if not isinstance(evidence, dict) or evidence.get("files") != files:
            issues.append("audit 文件快照已漂移")
        elif evidence.get("digest") != evidence_digest(files):
            issues.append("audit evidence digest 不一致")
    except ValueError as exc:
        issues.append(str(exc))
    provenance = binding.get("provenance")
    if not isinstance(provenance, dict) or not provenance.get("framework_revision") or not provenance.get("consumer_revision"):
        issues.append("绑定缺少框架或消费仓 revision")
    passed = not issues
    evidence_digest_value = ((binding.get("evidence") or {}).get("digest") if isinstance(binding.get("evidence"), dict) else "")
    output = {
        "pass": passed,
        "reason": "independent finalize audit review" if passed else "; ".join(issues),
        "provenance": {
            "role": "judge",
            "backend": "external",
            "independent": True,
            "host": "pmai-finalize-readonly-judge",
            "model": "deterministic-finalize-audit-v1",
            "run_id": f"finalize-judge-{evidence_digest_value[:16]}",
            "framework_revision": git_revision(SCRIPT_DIR.parent),
            "tool_sha256": file_digest(Path(__file__).resolve()),
        },
        "evidence_digest": evidence_digest_value,
    }
    print(json.dumps(output, ensure_ascii=False))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
