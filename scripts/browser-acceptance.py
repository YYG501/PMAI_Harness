#!/usr/bin/env python3
"""Run all affected Web acceptance flows in one persistent browser chain."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from _lib.browser_evidence import (
    LEGACY_BROWSER_CHECK_COVERAGE,
    browser_batch_digest,
)


REQUIRED_COVERAGE = {"smoke", "visual", "behavior"}
ALLOWED_COMMANDS = {
    "attrs",
    "back",
    "click",
    "console",
    "css",
    "fill",
    "forward",
    "goto",
    "hover",
    "is",
    "js",
    "network",
    "press",
    "reload",
    "responsive",
    "screenshot",
    "scroll",
    "select",
    "snapshot",
    "text",
    "type",
    "url",
    "viewport",
    "wait",
}
ASSERTION_COMMANDS = {"is", "js", "wait"}
INTERACTION_COMMANDS = {"click", "fill", "press", "select", "type"}
VISUAL_COMMANDS = {"screenshot"}


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def read_json(path: Path, label: str) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"{label} 不存在：{path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"{label} 不是合法 JSON：{path}: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"{label} 顶层必须是对象：{path}")
    return value


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def write_legacy_artifacts(
    audit_path: Path, artifact: dict, checks: list[str]
) -> dict[str, str]:
    digest = browser_batch_digest(artifact)
    artifact["batch_digest"] = digest
    written: dict[str, str] = {}
    for check in checks:
        coverage = LEGACY_BROWSER_CHECK_COVERAGE[check]
        path = audit_path.parent / f"{check}.json"
        value = {
            "schema_version": 1,
            "check": check,
            "status": artifact["status"],
            "implementation_commit": artifact["implementation_commit"],
            "source_hash": artifact.get("source_hash"),
            "derived_from": audit_path.name,
            "browser_batch_digest": digest,
            "single_chain_invocation": True,
            "covers": [coverage],
            "flows": [
                {
                    "id": flow["id"],
                    "route": flow["route"],
                    "status": flow["status"],
                }
                for flow in artifact["flows"]
                if coverage in flow.get("covers", [])
            ],
        }
        if check == "browser-smoke":
            value["active_browser_smoke"] = artifact["active_browser_smoke"]
        if check == "visual":
            value["visual_artifacts"] = artifact.get("visual_artifacts", [])
            value["missing_visual_artifacts"] = artifact.get(
                "missing_visual_artifacts", []
            )
            value["findings"] = [] if artifact["status"] == "pass" else [
                {"reason": "browser batch failed"}
            ]
        write_json(path, value)
        written[check] = str(path)
    return written


def resolve_path(value: str, repo_root: Path) -> Path:
    candidate = Path(value).expanduser()
    return candidate.resolve() if candidate.is_absolute() else (repo_root / candidate).resolve()


def read_build(module_dir: Path) -> dict:
    meta = read_json(module_dir / ".work-meta.json", "build 合同")
    build = meta.get("build")
    if not isinstance(build, dict):
        raise SystemExit(".work-meta.json 缺少 build 合同。")
    commit = str(build.get("implementation_commit") or "").strip()
    finalization = build.get("finalization")
    if not commit:
        raise SystemExit("build 合同缺少 implementation_commit。")
    if not isinstance(finalization, dict) or not finalization.get("requested_at"):
        raise SystemExit("PM 尚未请求定稿，不能运行最终浏览器验收。")
    if str(finalization.get("requested_commit") or "") != commit:
        raise SystemExit("定稿请求与 implementation_commit 不一致。")
    return build


def find_browse_binary(explicit: str | None, repo_root: Path) -> Path:
    candidates = [
        explicit,
        os.environ.get("GSTACK_BROWSE_BIN"),
        shutil.which("browse"),
        str(repo_root / ".claude/skills/gstack/browse/dist/browse"),
        str(Path.home() / ".Codex/skills/gstack/browse/dist/browse"),
        str(Path.home() / ".agents/skills/gstack/browse/dist/browse"),
        str(Path.home() / ".claude/skills/gstack/browse/dist/browse"),
        str(Path.home() / ".claude/skills/gstack/.agents/skills/gstack-browse/dist/browse"),
    ]
    for value in candidates:
        if value:
            path = Path(value).expanduser()
            if path.is_file() and os.access(path, os.X_OK):
                return path.resolve()
    raise SystemExit(
        "找不到可执行的 gstack browse；设置 GSTACK_BROWSE_BIN 或启用当前 runtime browser。"
    )


def expand(value: str, *, base_url: str, audit_dir: Path) -> str:
    return value.replace("{base_url}", base_url).replace("{audit_dir}", str(audit_dir))


def timing_command(audit_path: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(Path(__file__).with_name("build-timing.py")),
            *args,
            "--audit-file",
            str(audit_path.parent / "timing.json"),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def start_timing(audit_path: Path) -> str:
    result = timing_command(
        audit_path, "start", "--phase", "browser-acceptance", "--kind", "final"
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or "无法开始 browser-acceptance timing。")
    return str(json.loads(result.stdout)["id"])


def finish_timing(audit_path: Path, entry_id: str, status: str, reason: str | None) -> str | None:
    args = ["finish", "--id", entry_id, "--status", status]
    if reason:
        args.extend(["--reason", reason])
    result = timing_command(audit_path, *args)
    return result.stderr.strip() or "timing finish failed" if result.returncode != 0 else None


def same_origin(url: str, base_url: str) -> bool:
    actual = urlsplit(url)
    base = urlsplit(base_url)
    return actual.scheme == base.scheme and actual.netloc == base.netloc


def compile_manifest(
    manifest: dict, audit_dir: Path
) -> tuple[list[list[str]], list[dict], list[Path]]:
    if manifest.get("schema_version") != 1:
        raise SystemExit("browser acceptance manifest schema_version 必须是 1。")
    base_url = str(manifest.get("base_url") or "").rstrip("/")
    parsed_base = urlsplit(base_url)
    if parsed_base.scheme not in {"http", "https"} or not parsed_base.netloc:
        raise SystemExit("browser acceptance manifest.base_url 必须是 http(s) URL。")
    flows = manifest.get("flows")
    if not isinstance(flows, list) or not flows:
        raise SystemExit("browser acceptance manifest.flows 必须是非空数组。")

    chain: list[list[str]] = []
    summaries: list[dict] = []
    visual_paths: list[Path] = []
    seen_ids: set[str] = set()
    covered: set[str] = set()
    for index, raw_flow in enumerate(flows, 1):
        if not isinstance(raw_flow, dict):
            raise SystemExit(f"browser flow #{index} 必须是对象。")
        flow_id = str(raw_flow.get("id") or "").strip()
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", flow_id):
            raise SystemExit(f"browser flow #{index} id 不合法。")
        if flow_id in seen_ids:
            raise SystemExit(f"browser flow id 重复：{flow_id}")
        seen_ids.add(flow_id)
        route = str(raw_flow.get("route") or "").strip()
        if not route.startswith("/"):
            raise SystemExit(f"browser flow {flow_id} route 必须以 / 开头。")
        covers = raw_flow.get("covers")
        if (
            not isinstance(covers, list)
            or not covers
            or any(str(value) not in REQUIRED_COVERAGE for value in covers)
        ):
            raise SystemExit(
                f"browser flow {flow_id} covers 只能包含 smoke / visual / behavior。"
            )
        flow_covers = {str(value) for value in covers}
        commands = raw_flow.get("commands")
        if not isinstance(commands, list) or not commands:
            raise SystemExit(f"browser flow {flow_id} commands 必须是非空数组。")

        compiled: list[list[str]] = []
        for command_index, raw_command in enumerate(commands, 1):
            if (
                not isinstance(raw_command, list)
                or not raw_command
                or any(not isinstance(value, str) for value in raw_command)
            ):
                raise SystemExit(
                    f"browser flow {flow_id} command #{command_index} 必须是字符串数组。"
                )
            command = [
                expand(value, base_url=base_url, audit_dir=audit_dir) for value in raw_command
            ]
            if command[0] not in ALLOWED_COMMANDS:
                raise SystemExit(
                    f"browser flow {flow_id} 使用了未允许的命令：{command[0]}"
                )
            if command[0] == "goto":
                if (
                    len(command) != 2
                    or not same_origin(command[1], base_url)
                    or urlsplit(command[1]).path != route
                ):
                    raise SystemExit(
                        f"browser flow {flow_id} goto 必须是 manifest.base_url + route。"
                    )
            if command[0] == "screenshot":
                if len(command) != 2:
                    raise SystemExit(
                        f"browser flow {flow_id} screenshot 必须提供一个证据文件路径。"
                    )
                screenshot_path = Path(command[1]).expanduser().resolve()
                try:
                    screenshot_path.relative_to(audit_dir.resolve())
                except ValueError as exc:
                    raise SystemExit(
                        f"browser flow {flow_id} screenshot 必须写入 audit 目录。"
                    ) from exc
                visual_paths.append(screenshot_path)
            compiled.append(command)

        names = [command[0] for command in compiled]
        if "goto" not in names:
            raise SystemExit(f"browser flow {flow_id} 缺少 goto，不能证明页面主动加载。")
        if "smoke" in flow_covers and not (set(names) & ASSERTION_COMMANDS):
            raise SystemExit(f"browser flow {flow_id} 声称覆盖 smoke，但没有主动断言。")
        if "visual" in flow_covers and not (set(names) & VISUAL_COMMANDS):
            raise SystemExit(f"browser flow {flow_id} 声称覆盖 visual，但没有截图。")
        if "behavior" in flow_covers:
            interaction_indexes = [
                position for position, name in enumerate(names) if name in INTERACTION_COMMANDS
            ]
            assertion_indexes = [
                position for position, name in enumerate(names) if name in ASSERTION_COMMANDS
            ]
            if not interaction_indexes or not any(
                assertion > interaction_indexes[0] for assertion in assertion_indexes
            ):
                raise SystemExit(
                    f"browser flow {flow_id} 声称覆盖 behavior，"
                    "但没有交互后的主动断言。"
                )
        covered.update(flow_covers)
        chain.extend(compiled)
        summaries.append(
            {
                "id": flow_id,
                "route": route,
                "covers": sorted(flow_covers),
                "commands": len(compiled),
            }
        )

    missing = sorted(REQUIRED_COVERAGE - covered)
    if missing:
        raise SystemExit("browser acceptance 批次缺少覆盖：" + "、".join(missing))
    return chain, summaries, visual_paths


def run(args: argparse.Namespace) -> int:
    repo_root = Path(args.repo_root).expanduser().resolve()
    module_dir = resolve_path(args.module_dir, repo_root)
    manifest_path = resolve_path(args.manifest, repo_root)
    audit_path = resolve_path(args.audit, repo_root)
    build = read_build(module_dir)
    manifest = read_json(manifest_path, "browser acceptance manifest")
    chain, flows, visual_paths = compile_manifest(manifest, audit_path.parent)
    browse = find_browse_binary(args.browse_bin, repo_root)
    manifest_hash = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    log_path = audit_path.with_suffix(".log")
    artifact = {
        "schema_version": 1,
        "check": "browser-acceptance",
        "status": "running",
        "implementation_commit": build["implementation_commit"],
        "source_hash": build.get("approved_source_hash"),
        "manifest": str(manifest_path),
        "manifest_hash": manifest_hash,
        "started_at": now_iso(),
        "ended_at": None,
        "active_browser_smoke": False,
        "single_chain_invocation": True,
        "covers": sorted(REQUIRED_COVERAGE),
        "flows": flows,
        "log": str(log_path),
    }
    write_json(audit_path, artifact)
    timing_id = start_timing(audit_path)
    artifact["timing_entry_id"] = timing_id
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w", encoding="utf-8") as log:
        result = subprocess.run(
            [str(browse), "chain"],
            cwd=repo_root,
            input=json.dumps(chain, ensure_ascii=False),
            text=True,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )
    missing_visuals = [str(path) for path in visual_paths if not path.is_file() or path.stat().st_size == 0]
    passed = result.returncode == 0 and not missing_visuals
    artifact["ended_at"] = now_iso()
    artifact["status"] = "pass" if passed else "fail"
    artifact["active_browser_smoke"] = passed
    artifact["exit_code"] = result.returncode
    artifact["visual_artifacts"] = [str(path) for path in visual_paths]
    artifact["missing_visual_artifacts"] = missing_visuals
    for flow in artifact["flows"]:
        flow["status"] = artifact["status"]
    legacy_checks = list(dict.fromkeys(args.legacy_check))
    if legacy_checks:
        artifact["legacy_adapter"] = {
            "checks": legacy_checks,
            "artifacts": write_legacy_artifacts(audit_path, artifact, legacy_checks),
        }
    timing_error = finish_timing(
        audit_path,
        timing_id,
        artifact["status"],
        "browser chain failed" if not passed else None,
    )
    if timing_error:
        artifact["timing_error"] = timing_error
    write_json(audit_path, artifact)
    if not passed:
        print(f"❌ 浏览器批量验收失败，详见 {log_path}", file=sys.stderr)
    else:
        print(json.dumps(artifact, ensure_ascii=False))
    return 0 if passed else 1


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--repo-root", default=".")
    result.add_argument("--module-dir", required=True)
    result.add_argument("--manifest", required=True)
    result.add_argument("--audit", required=True)
    result.add_argument("--browse-bin")
    result.add_argument(
        "--legacy-check",
        action="append",
        default=[],
        choices=sorted(LEGACY_BROWSER_CHECK_COVERAGE),
    )
    return result


def main(argv: list[str] | None = None) -> int:
    try:
        return run(parser().parse_args(argv))
    except SystemExit as exc:
        if isinstance(exc.code, str):
            print(f"❌ {exc.code}", file=sys.stderr)
            return 1
        raise


if __name__ == "__main__":
    raise SystemExit(main())
