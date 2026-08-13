#!/usr/bin/env python3
"""Bind the correct Git candidate to the Build contract, then resume finalization.

This is the stable mechanical entry used after the PM requests finalization. It
does not decide whether the candidate is acceptable; Build still owns that
decision and the semantic checks requested by ``finalize-work.py``.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def run(command: list[str], *, cwd: Path) -> int:
    return subprocess.run(command, cwd=cwd, check=False).returncode


def git_root(module_dir: Path) -> Path:
    result = subprocess.run(
        ["git", "-C", str(module_dir), "rev-parse", "--show-toplevel"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        detail = result.stderr.strip()
        raise SystemExit("无法定位 build 仓库" + (f"：{detail}" if detail else "。"))
    return Path(result.stdout.strip()).resolve()


def finalize_candidate(args: argparse.Namespace) -> int:
    script_dir = Path(__file__).resolve().parent
    module_dir = Path(args.module_dir).expanduser().resolve()
    repo_root = git_root(module_dir)
    recorded = run(
        [
            sys.executable,
            str(script_dir / "build-contract.py"),
            "bind-candidate",
            str(module_dir),
        ],
        cwd=repo_root,
    )
    if recorded != 0:
        return recorded

    command = [
        sys.executable,
        str(script_dir / "finalize-work.py"),
        "--module-dir",
        str(module_dir),
    ]
    if args.browser_manifest:
        command.extend(["--browser-manifest", args.browser_manifest])
    if args.browse_bin:
        command.extend(["--browse-bin", args.browse_bin])
    if args.coverage_plan:
        command.extend(["--coverage-plan", args.coverage_plan])
    if args.coverage_artifacts:
        command.extend(["--coverage-artifacts", args.coverage_artifacts])
    for check_id in args.coverage_confirm_state:
        command.extend(["--coverage-confirm-state", check_id])
    if args.retry_failed:
        command.append("--retry-failed")
    if args.no_land:
        command.append("--no-land")
    return run(command, cwd=repo_root)


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--module-dir", required=True)
    result.add_argument("--browser-manifest")
    result.add_argument("--browse-bin")
    result.add_argument("--coverage-plan")
    result.add_argument("--coverage-artifacts")
    result.add_argument("--coverage-confirm-state", action="append", default=[])
    result.add_argument("--retry-failed", action="store_true")
    result.add_argument("--no-land", action="store_true")
    return result


def main(argv: list[str] | None = None) -> int:
    try:
        return finalize_candidate(parser().parse_args(argv))
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"ERROR: {exc.code}", file=sys.stderr)
            return 1
        raise


if __name__ == "__main__":
    raise SystemExit(main())
