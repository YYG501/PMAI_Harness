#!/usr/bin/env python3
"""Compatibility guard for the retired requirements/ -> docs/modules migration.

The current PMAI lifecycle no longer creates requirements/active|closed. Older
CHANGELOG entries told users to run this script before upgrading legacy consumer
repos, so keep the command alive and make it fail loud instead of producing a
"file not found" dead end.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _req_dirs(root: Path) -> list[Path]:
    found: list[Path] = []
    for bucket in ("active", "closed"):
        base = root / "requirements" / bucket
        if not base.exists():
            continue
        found.extend(sorted(p for p in base.iterdir() if p.is_dir()))
    return found


def _read_meta(req_dir: Path) -> dict:
    for name in (".req-meta.json", "req.meta.json", "req-meta.json"):
        meta = req_dir / name
        if not meta.exists():
            continue
        try:
            data = json.loads(meta.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else {}
        except Exception:
            return {"_meta_error": f"could not parse {meta.name}"}
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Inspect legacy requirements/active|closed trees. The automatic "
            "migration was retired; this command now gives an explicit upgrade "
            "stop instead of a missing-script error."
        )
    )
    parser.add_argument(
        "repo",
        nargs="?",
        default=".",
        help="consumer repo to inspect (default: current directory)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="inventory legacy reqs without changing files")
    mode.add_argument("--apply", action="store_true", help="refuse automatic migration with explicit guidance")
    args = parser.parse_args()

    root = Path(args.repo).expanduser().resolve()
    reqs = _req_dirs(root)
    if not reqs:
        print("✅ No legacy requirements/active|closed tree found.")
        print("   Nothing to migrate; current PMAI uses docs/modules/<module>/ + .work-meta.json.")
        return 0

    print(f"⚠️  Found {len(reqs)} legacy req director{'y' if len(reqs) == 1 else 'ies'} under {root}/requirements:")
    for req in reqs:
        meta = _read_meta(req)
        status = meta.get("status") or ("active" if "/active/" in str(req) else "closed")
        stage = meta.get("stage", "?")
        module = meta.get("module") or meta.get("module_name") or "unknown-module"
        suffix = f" meta_error={meta['_meta_error']}" if "_meta_error" in meta else ""
        print(f"  - {req.relative_to(root)}  status={status} stage={stage} module={module}{suffix}")

    print("")
    print("Automatic migration is not safe in the current slim lifecycle because old req")
    print("directories do not contain a reliable one-to-one module identity. Do not copy")
    print("them mechanically into docs/modules/.")
    print("")
    print("Recommended path:")
    print("  1. Keep requirements/ as archive evidence.")
    print("  2. Open each live item with /pmai-design or /pmai-direction and write the")
    print("     current truth into docs/modules/<module>/discussion.md, decisions.md, spec.md.")
    print("  3. Continue with /pmai-build; PM acceptance automatically lands the result and records durable product state.")

    if args.apply:
        print("")
        print("❌ --apply refused: this compatibility command is inventory-only.")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
